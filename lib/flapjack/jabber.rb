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
require 'flapjack/version'

module Flapjack

  class Jabber < Blather::Client

    include Flapjack::Pikelet
    include Flapjack::Utility

    log = Logger.new(STDOUT)
    # log.level = Logger::DEBUG
    log.level = Logger::INFO
    Blather.logger = log

    def initialize
      super
      @buffer = []
      @hostname = Socket.gethostname
    end

    def setup
      @redis = build_redis_connection_pool
      @flapjack_jid = Blather::JID.new((@config['jabberid'] || 'flapjack') + '/' + @hostname)

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

      register_handler :message, :chat? do |stanza|
        EM.next_tick do
          EM.synchrony do
            on_chat(stanza)
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
      if @config['rooms'] && @config['rooms'].length > 0
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
      return if @buffer.empty?
      while stanza = @buffer.shift
        @logger.debug("Sending a buffered jabber message to: #{stanza.to}, using: #{stanza.type}, message: #{stanza.body}")
        write(stanza)
      end
    end

    def interpreter(command)
      msg          = nil
      action       = nil
      entity_check = nil
      case
      when command =~ /^ACKID\s+(\d+)(?:\s*(.*?)(?:\s*duration.*?(\d+.*\w+.*))?)$/i;
        ackid        = $1
        comment      = $2
        duration_str = $3

        error = nil
        dur   = nil

        if comment.nil? || (comment.length == 0)
          error = "please provide a comment, eg \"flapjack: ACKID #{$1} AL looking\""
        elsif duration_str
          # a fairly liberal match above, we'll let chronic_duration do the heavy lifting
          dur = ChronicDuration.parse(duration_str)
        end

        four_hours = 4 * 60 * 60
        duration = (dur.nil? || (dur <= 0)) ? four_hours : dur

        event_id = @redis_handler.hget('unacknowledged_failures', ackid)

        if event_id.nil?
          error = "not found"
        else
          entity_check = Flapjack::Data::EntityCheck.for_event_id(event_id, :redis => @redis_handler)
          error = "unknown entity" if entity_check.nil?
        end

        if entity_check && entity_check.in_unscheduled_maintenance?
          error = "#{event_id} is already acknowledged"
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

      when command =~ /^help$/
        msg  = "commands: \n"
        msg += "  ACKID <id> <comment> [duration: <time spec>] \n"
        msg += "  identify \n"
        msg += "  help \n"

      when command =~ /^identify$/
        t = Process.times
        boot_time = Time.at(@redis_handler.get('boot_time').to_i)
        msg  = "Flapjack #{Flapjack::VERSION} process #{Process.pid} on #{`hostname -f`.chomp} \n"
        msg += "Boot time: #{boot_time}\n"
        msg += "User CPU Time: #{t.utime}\n"
        msg += "System CPU Time: #{t.stime}\n"
        msg += `uname -a`.chomp + "\n"

      when command =~ /^(.*)/
        words = $1
        msg   = "what do you mean, '#{words}'? Type 'help' for a list of acceptable commands."

      end

      {:msg => msg, :action => action}
    end

    def on_groupchat(stanza)
      return if should_quit?
      logger.debug("groupchat message received: #{stanza.inspect}")

      if stanza.body =~ /^flapjack:\s+(.*)/
        command = $1
      end

      results = interpreter(command)
      msg     = results[:msg]
      action  = results[:action]

      if msg || action
        say(stanza.from.stripped, msg, :groupchat)
        logger.debug("Sent to group chat: #{msg}")
        action.call if action
      end
    end

    def on_chat(stanza)
      return if should_quit?
      logger.debug("chat message received: #{stanza.inspect}")

      if stanza.body =~ /^flapjack:\s+(.*)/
        command = $1
      else
        command = stanza.body
      end

      results = interpreter(command)
      msg     = results[:msg]
      action  = results[:action]

      if msg || action
        say(stanza.from.stripped, msg, :chat)
        logger.debug("Sent to #{stanza.from.stripped}: #{msg}")
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
      stanza = Blather::Stanza::Message.new(to, msg, using)
      if connected?
        @logger.debug("Sending a jabber message to: #{to.to_s}, using: #{using.to_s}, message: #{msg}")
        write(stanza)
      else
        @logger.debug("Buffering a jabber message to: #{to.to_s}, using: #{using.to_s}, message: #{msg}")
        @buffer << stanza
      end
    end

    def add_shutdown_event(opts = {})
      return unless redis = opts[:redis]
      redis.rpush(@config['queue'], JSON.generate('notification_type' => 'shutdown'))
    end

    def main
      logger.debug("New Jabber pikelet with the following options: #{@config.inspect}")

      count_timer = EM::Synchrony.add_periodic_timer(30) do
        logger.debug("connection count: #{EM.connection_count} #{Time.now.to_s}.#{Time.now.usec.to_s}")
      end

      keepalive_timer = EM::Synchrony.add_periodic_timer(60) do
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
          events[queue] = @redis.blpop(queue, 0)
          event         = Yajl::Parser.parse(events[queue][1])
          type          = event['notification_type']
          logger.debug('jabber notification event received')
          logger.debug(event.inspect)
          if 'shutdown'.eql?(type)
            if should_quit?
              EM.next_tick do
                # get delays without the next_tick
                close # Blather::Client.close
              end
            end
          else
            entity, check = event['event_id'].split(':')
            state         = event['state']
            summary       = event['summary']
            duration      = event['duration'] ? time_period_in_words(event['duration']) : '4 hours'
            address       = event['address']

            logger.debug("processing jabber notification address: #{address}, event: #{entity}:#{check}, state: #{state}, summary: #{summary}")

            ack_str = event['event_count'] && !state.eql?('ok') && !'acknowledgement'.eql?(type) ?
              "::: flapjack: ACKID #{event['event_count']} " : ''

            maint_str = (type && 'acknowledgement'.eql?(type)) ?
              "has been acknowledged, unscheduled maintenance created for #{duration}" :
              "is #{state.upcase}"

            msg = "#{type.upcase} #{ack_str}::: \"#{check}\" on #{entity} #{maint_str} ::: #{summary}"

            chat_type = :chat
            chat_type = :groupchat if @config['rooms'] && @config['rooms'].include?(address)
            EM.next_tick do
              say(Blather::JID.new(address), msg, chat_type)
            end
          end
        else
          logger.debug("not connected, sleep 1 before retry")
          EM::Synchrony.sleep(1)
        end
      end

      count_timer.cancel
      keepalive_timer.cancel

      @redis.empty! if @redis
      @redis_handler.empty! if @redis_handler
    end

  end
end

