#!/usr/bin/env ruby

require 'em-synchrony/fiber_iterator'
require 'blather/client/dsl'
require 'socket'

module Flapjack
  module Notification

    class JabberConnection
      extend Blather::DSL

      def keepalive()
        client.write ' '
      end

    end

    class Jabber

      include Flapjack::Pikelet

      def initialize(opts)
        # TODO: create a logger named jabber
        self.bootstrap
        @logger.debug("New Jabber pikelet with the following options: #{opts.inspect}")
        @config   = opts[:config]
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

      def main

        @logger.debug("in main jabber")

        # FIXME: remove the EM.synchrony call ?
        # The EM.synchrony here is redundant when running this from flapjack-coordinator, as it is
        # already running this code within the context of EM Synchrony. leaving it in here seems to
        # have no effect however.
        EM.synchrony do

          @jabber_connection = Flapjack::Notification::JabberConnection.new
          @logger.debug("Setting up jabber connection with jabberid: " + @flapjack_jid.to_s + ", port: " + @config['port'].to_s + ", server: " + @config['server'].to_s + ", password: " + @config['password'].to_s)
          @jabber_connection.send(:client).setup @flapjack_jid, @config['password'], @config['server'], @config['port'].to_i

          @jabber_connection.disconnected do
            @logger.warn("jabbers disconnected! reconnecting in 1 second ...")
            #EM::Synchrony.sleep(5)
            #EM.sleep(5)
            sleep 1
            @jabber_connection.send(:client).connect
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
              @jabber_connection.send(:client).write presence
              @jabber_connection.say(room, "flapjack jabber gateway started at #{Time.now}, hello!", :groupchat)
            end
          end

          @jabber_connection.message :groupchat?, :body => /^flapjack: / do |m|
            @logger.debug("groupchat message received: #{m.inspect}")
            rxp = Regexp.new('flapjack: (.*)', 'i').match(m.body)
            skip unless rxp.length > 1
            words = rxp[1]
            msg = "what do you mean, '#{words}'?"
            #from_room, from_alias = Regexp.new('(.*)/(.*)', 'i').match(m.from)
            @jabber_connection.say(m.from.stripped, msg, :groupchat)
            @logger.debug("Sent to group chat: #{msg}")
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
            redis = ::Redis.new(:driver => :synchrony)
            @logger.debug("kicking off a fiber for #{queue}")
            EM::Synchrony.sleep(1)
            happy = true
            while happy
              if jabber_connected
                @logger.debug("jabber is connected so commencing blpop on #{queue}")
                events[queue] = redis.blpop(queue)
                event         = Yajl::Parser.parse(events[queue][1])
                type          = event['notification_type']
                entity, check = event['event_id'].split(':')
                state         = event['state']
                summary       = event['summary']
                @config['rooms'].each do |room|
                  @jabber_connection.say(Blather::JID.new(room), "#{type.upcase} ::: \"#{check}\" on #{entity} is #{state.upcase} ::: #{summary}", :groupchat)
                end
              else
                @logger.debug("bugger, not connected, sleep 1 before retry")
                EM::Synchrony.sleep(1)
              end
            end
          end # FiberIterator do

        end
      end

    end
  end
end

