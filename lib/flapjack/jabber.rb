#!/usr/bin/env ruby

require 'socket'

require 'eventmachine'
# the redis/synchrony gems need to be required in this particular order, see
# the redis-rb README for details
require 'hiredis'
require 'em-synchrony'
require 'redis/connection/synchrony'
require 'redis'

require 'chronic_duration'

require 'blather/client/client'
require 'em-synchrony/fiber_iterator'
require 'yajl/json_gem'

require 'flapjack/data/entity_check'
require 'flapjack/pikelet'
require 'flapjack/utility'

module Flapjack

  class Jabber < Blather::Client

    include Flapjack::Pikelet
    include Flapjack::Utility

    log = Logger.new(STDOUT)
    # log.level = Logger::DEBUG
    log.level = Logger::INFO
    Blather.logger = log

    def setup
      @redis = build_redis_connection_pool
      hostname = Socket.gethostname
      @flapjack_jid = Blather::JID.new((@config['jabberid'] || 'flapjack') + '/' + hostname)

      super(@flapjack_jid, @config['password'], @config['server'], @config['port'].to_i)

      logger.debug("Building jabber connection with jabberid: " +
        @flapjack_jid.to_s + ", port: " + @config['port'].to_s +
        ", server: " + @config['server'].to_s + ", password: " +
        @config['password'].to_s)

      register_handler :ready do |stanza|
        EM.next_tick do
          EM.synchrony do
            on_ready(stanza)
          end
        end
      end

      register_handler :message, :groupchat?, :body => /^flapjack:\s+/ do |stanza|
        EM.next_tick do
          EM.synchrony do
            on_groupchat(stanza)
          end
        end
      end

      register_handler :disconnected do |stanza|
        ret = true
        EM.next_tick do
          EM.synchrony do
            ret = on_disconnect(stanza)
          end
        end
        ret
      end
    end

    # Join the MUC Chat room after connecting.
    def on_ready(stanza)
      return if should_quit?
      @redis_handler ||= build_redis_connection_pool
      @connected_at = Time.now.to_i
      logger.info("Jabber Connected")
      @config['rooms'].each do |room|
        logger.info("Joining room #{room}")
        presence = Blather::Stanza::Presence.new
        presence.from = @flapjack_jid
        presence.to = Blather::JID.new("#{room}/#{@config['alias']}")
        presence << "<x xmlns='http://jabber.org/protocol/muc'/>"
        write presence
        say(room, "flapjack jabber gateway started at #{Time.now}, hello!", :groupchat)
      end
    end

    def on_groupchat(stanza)
      return if should_quit?
      logger.debug("groupchat message received: #{stanza.inspect}")

      msg = nil
      action = nil
      redis = nil
      entity_check = nil
      if stanza.body =~ /^flapjack:\s+ACKID\s+(\d+)(?:\s*(.*?)(?:\s*duration.*?(\d+.*\w+.*))?)$/i;
        ackid   = $1
        comment = $2
        duration_str = $3

        error = nil
        dur = nil

        if comment.nil? || (comment.length == 0)
          error = "please provide a comment, eg \"flapjack: ACKID #{$1} AL looking\""
        elsif duration_str
          # a fairly liberal match above, we'll let chronic_duration do the heavy lifting
          dur = ChronicDuration.parse(duration_str)
        end

        four_hours = 4 * 60 * 60
        duration = (dur.nil? || (dur <= 0) || (dur > four_hours)) ? four_hours : dur

        event_id = @redis_handler.hget('unacknowledged_failures', ackid)

        if event_id.nil?
          error = "not found"
        else
          entity_check = Flapjack::Data::EntityCheck.for_event_id(event_id, :redis => @redis_handler)
          error = "unknown entity" if entity_check.nil?
        end

        if error
          msg = "ERROR - couldn't ACK #{ackid} - #{error}"
        else
          msg = "ACKing #{entity_check.check} on #{entity_check.entity_name} (#{ackid})"
          action = Proc.new {
            entity_check.create_acknowledgement('summary' => (comment || ''),
              'acknowledgement_id' => ackid, 'duration' => duration)
          }
        end

      elsif stanza.body =~ /^flapjack: (.*)/i
        words = $1
        msg   = "what do you mean, '#{words}'?"
      end

      if msg || action
        #from_room, from_alias = Regexp.new('(.*)/(.*)', 'i').match(m.from)
        say(stanza.from.stripped, msg, :groupchat)
        logger.debug("Sent to group chat: #{msg}")
        action.call if action
      end
    end

    # returning true to prevent the reactor loop from stopping
    def on_disconnect(stanza)
      return true if should_quit?
      logger.warn("jabbers disconnected! reconnecting in 1 second ...")
      EventMachine::Timer.new(1) do
        connect # Blather::Client.connect
      end
      true
    end

    def say(to, msg, using = :chat)
      @logger.debug("Sending a jabber message to: #{to.to_s}, using: #{using.to_s}, message: #{msg}")
      write Blather::Stanza::Message.new(to, msg, using)
    end

    def add_shutdown_event(opts = {})
      return unless redis = opts[:redis]
      redis.rpush(@config['queue'], JSON.generate('notification_type' => 'shutdown'))
    end

    def main
      logger.debug("New Jabber pikelet with the following options: #{@config.inspect}")

      EM::Synchrony.add_periodic_timer(30) do
        logger.debug("connection count: #{EM.connection_count} #{Time.now.to_s}.#{Time.now.usec.to_s}")
      end

      EM::Synchrony.add_periodic_timer(60) do
        logger.debug("calling keepalive on the jabber connection")
        write(' ') if connected?
      end

      setup
      connect # Blather::Client.connect

      # simplified to use a single queue only as it makes the shutdown logic easier
      queue = @config['queue']
      events = {}

      until should_quit?

        # FIXME: should also check if presence has been established in any group chat rooms that are
        # configured before starting to process events, otherwise the first few may get lost (send
        # before joining the group chat rooms)
        if connected?
          logger.debug("jabber is connected so commencing blpop on #{queue}")
          events[queue] = @redis.blpop(queue)
          event         = Yajl::Parser.parse(events[queue][1])
          type          = event['notification_type']
          logger.debug('jabber notification event received')
          logger.debug(event.inspect)
          if 'shutdown'.eql?(type)
            EM.next_tick do
              # get delays without the next_tick
              close # Blather::Client.close
            end
          else
            entity, check = event['event_id'].split(':')
            state         = event['state']
            summary       = event['summary']
            logger.debug("processing jabber notification event: #{entity}:#{check}, state: #{state}, summary: #{summary}")

            # FIXME: change the 'for 4 hours' so it looks up the length of unscheduled maintance
            # that has been created, or takes this value from the event. This is so we can handle
            # varying lengths of acknowledgement-created-unscheduled-maintenace.
            ack_str = event['event_count'] && !state.eql?('ok') ?
              "::: flapjack: ACKID #{event['event_count']} " : ''

            maint_str = (type && 'acknowledgement'.eql?(type.downcase)) ?
              "has been acknowledged, unscheduled maintenance created for #{time_period_in_words(event['duration'])}" :
              "is #{state.upcase}"

            msg = "#{type.upcase} #{ack_str}::: \"#{check}\" on #{entity} #{maint_str} ::: #{summary}"

            EM.next_tick do
              @config['rooms'].each do |room|
                say(Blather::JID.new(room), msg, :groupchat)
              end
            end
          end
        else
          logger.debug("not connected, sleep 1 before retry")
          EM::Synchrony.sleep(1)
        end
      end
    end

  end
end

