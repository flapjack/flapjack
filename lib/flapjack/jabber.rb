#!/usr/bin/env ruby

require 'socket'

require 'eventmachine'
# the redis/synchrony gems need to be required in this particular order, see
# the redis-rb README for details
require 'hiredis'
require 'em-synchrony'
require 'redis/connection/synchrony'
require 'redis'

require 'blather/client/dsl'
require 'em-synchrony/fiber_iterator'
require 'yajl/json_gem'

module Flapjack

  class JabberConnection
    include Blather::DSL

    def keepalive()
      client.write ' '
    end

  end

  class Jabber

    include Flapjack::Pikelet

    def initialize(opts = {})
      # TODO: create a logger named jabber
      self.bootstrap
      @redis  = opts[:redis]
      @redis_config = opts[:redis_config]

      @config = opts[:config].dup
      @logger.debug("New Jabber pikelet with the following options: #{opts.inspect}")
      @hostname = Socket.gethostname
      @flapjack_jid = Blather::JID.new(@config['jabberid'] + '/' + @hostname)
    end

    def run
      @jabber_connection.send(:client).run
      logger = Logger.new(STDOUT)
      #logger.level = Logger::DEBUG
      logger.level = Logger::INFO
      Blather.logger = logger
    end

    def jabber_connected
      @jabber_connection.send(:client).connected?
    end

    def add_shutdown_event
      r = ::Redis.new(@redis_config)
      r.rpush(@config['queue'], JSON.generate('notification_type' => 'shutdown'))
      r.quit
    end

    def main

      @logger.debug("in main jabber")

      # FIXME: remove the EM.synchrony call ?
      # The EM.synchrony here is redundant when running this from flapjack-coordinator, as it is
      # already running this code within the context of EM Synchrony. leaving it in here seems to
      # have no effect however.
      EM.synchrony do

        @jabber_connection = Flapjack::JabberConnection.new
        @logger.debug("Setting up jabber connection with jabberid: " + @flapjack_jid.to_s + ", port: " + @config['port'].to_s + ", server: " + @config['server'].to_s + ", password: " + @config['password'].to_s)
        @jabber_connection.setup @flapjack_jid, @config['password'], @config['server'], @config['port'].to_i

        @jabber_connection.disconnected do
          unless should_quit?
            @logger.warn("jabbers disconnected! reconnecting in 1 second ...")
            # EM::Synchrony.sleep(1)
            sleep 1
            @jabber_connection.send(:client).connect
          end
        end

        # Join the MUC Chat room after connecting.
        @jabber_connection.when_ready do
          @logger.info("Jabber Connected")
          @config['rooms'].each do |room|
            @logger.info("Joining room #{room}")
            presence = Blather::Stanza::Presence.new
            presence.from = @flapjack_jid
            presence.to = Blather::JID.new("#{room}/#{@config['alias']}")
            presence << "<x xmlns='http://jabber.org/protocol/muc'/>"
            @jabber_connection.write_to_stream presence
            @jabber_connection.say(room, "flapjack jabber gateway started at #{Time.now}, hello!", :groupchat)
          end
        end

        @jabber_connection.message :groupchat?, :body => /^flapjack:\s+/ do |m|
          @logger.debug("groupchat message received: #{m.inspect}")

          msg = nil
          action = nil
          redis = nil
          entity_check = nil
          if m.body =~ /^flapjack:\s+ACKID\s+(\d+)\s*$/i
            ackid = $1

            @logger.debug("matched ackid #{ackid}")

            redis = ::Redis.new(@redis_config)
            event_id = redis.hget('unacknowledged_failures', ackid)

            error = nil
            if event_id.nil?
              error = "not found"
            else
              entity_check = Flapjack::Data::EntityCheck.for_event_id(event_id, :redis => redis)
              error = "unknown entity" if entity_check.nil?
            end

            if error
              msg = "couldn't ACK #{ackid} - #{error}"
            else
              msg = "ACKing #{entity_check.check} on entity #{entity_check.entity_name}(#{ackid})"
              action = Proc.new {
                entity_check.create_acknowledgement('summary' => "by #{m.from}", 'acknowledgement_id' => ackid)
              }
            end

            @logger.debug("about to send msg #{msg}")

          elsif m.body =~ /^flapjack: (.*)/i
            words = $1
            msg = "what do you mean, '#{words}'?"
          end

          if msg
            #from_room, from_alias = Regexp.new('(.*)/(.*)', 'i').match(m.from)
            @jabber_connection.say(m.from.stripped, msg, :groupchat)
            @logger.debug("Sent to group chat: #{msg}")
          end

          action.call if action
          redis.quit if redis

        end

        run

        EM::Synchrony.add_periodic_timer(30) do
          @logger.debug("connection count: #{EM.connection_count} #{Time.now.to_s}.#{Time.now.usec.to_s}")
        end

        EM::Synchrony.add_periodic_timer(60) do
          @logger.debug("calling keepalive on the jabber connection")
          @jabber_connection.keepalive if jabber_connected
        end

        queues = [@config['queue']]
        events = {}
        EM::Synchrony::FiberIterator.new(queues, queues.length).each do |queue|
          @logger.debug("kicking off a fiber for #{queue}")
          EM::Synchrony.sleep(1)
          until should_quit?
            if jabber_connected
              @logger.debug("jabber is connected so commencing blpop on #{queue}")
              events[queue] = @redis.blpop(queue)
              event         = Yajl::Parser.parse(events[queue][1])
              type          = event['notification_type']
              @logger.debug(event.inspect)
              unless 'shutdown'.eql?(type)
                entity, check = event['event_id'].split(':')
                state         = event['state']
                summary       = event['summary']
                ack_str       = event['failure_count'] ? "::: flapjack: ACKID #{event['failure_count']} " : ''
                @config['rooms'].each do |room|
                  @jabber_connection.say(Blather::JID.new(room), "#{type.upcase} #{ack_str}:::\"#{check}\" on #{entity} is #{state.upcase} ::: #{summary}", :groupchat)
                end
              end
            else
              @logger.debug("not connected, sleep 1 before retry")
              EM::Synchrony.sleep(1)
            end
          end
        end # FiberIterator do

      end
    end

  end
end

