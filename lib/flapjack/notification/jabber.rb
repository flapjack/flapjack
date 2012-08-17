#!/usr/bin/env ruby

require 'eventmachine'
require 'em-synchrony'
require 'em-synchrony/fiber_iterator'
require 'blather/client/dsl'
require 'redis'
require 'redis/connection/synchrony'
require 'yajl'


module Flapjack
  module Notification


    class Jabber

      include Flapjack::Pikelet
      extend Blather::DSL

      def initialize(opts)
        # TODO: create a logger named jabber
        self.bootstrap
        Blather::DSL.client.setup 'jabberid', 'password', 'jabberserver', 5222
      end

      def run
        Blather::DSL.client.run
        logger = Logger.new(STDOUT)
        logger.level = Logger::DEBUG
        #logger.level = Logger::INFO
        Blather.logger = logger
      end

      def jabber_connected
        Blather::DSL.client.connected?
      end

      disconnected do
        puts "jabbers disconnected! reconnecting in 5 seconds ..."
        EM::Synchrony.sleep(5)
        client.connect
      end

      # Join the MUC Chat room after connecting.
      when_ready do
        puts "XMPP Connected"
        p = Blather::Stanza::Presence.new
        p.from = Blather::JID.new('flapjack@jabber.bulletproof.net/flapjack-jabber')
        p.to = "log@conference.jabber.bulletproof.net/flapjack-jabber"
        p << "<x xmlns='http://jabber.org/protocol/muc'/>"
        client.write p
        say("log@conference.jabber.bulletproof.net", "flapjack jabber gateway started at #{Time.now}, hello!", :groupchat)
        client.write " "
      end

      message :groupchat?, :body => /^flapjack:/ do |m|
        puts "From: #{m.from}"
        rxp = Regexp.new('flapjack: (.*)', 'i').match(m.body)
        puts rxp.inspect
        puts
        skip unless rxp.length > 1
        words = rxp[1]
        msg = "what do you mean, '#{words}'?"
        #m = Blather::Stanza::Message.new
        #m.to = "log@conference.jabber.bulletproof.net"
        #m.type = :groupchat
        #m.body = msg
        #client.write m
        go(msg)
        puts "Sent to group chat: #{msg}"
      end

      def self.go(str)
        puts "Posting to #log: #{str}"
        say("log@conference.jabber.bulletproof.net", str, :groupchat)
        client.write " "
      end

      def self.keepalive()
        puts "Sending some whitespace as a keepalive"
        client.write ' '
      end

      def main
        extend Blather::DSL
        @logger.debug("in main jabber")

        trap(:INT) {
          puts "got INT signal, exiting"
          Blather::DSL.client.unbind
          EM.stop
        }
        trap(:TERM) {
          puts "got TERM signal, exiting"
          Blather::DSL.client.unbind
          EM.stop
        }
        EM.synchrony do

          run

          EM::Synchrony.add_periodic_timer(10) do
            puts "connection count: #{EM.connection_count} #{Time.now.to_s}.#{Time.now.usec.to_s}"
          end

          queues = ['jabber_notifications']
          events = {}
          EM::Synchrony::FiberIterator.new(queues, queues.length).each do |queue|
            redis = ::Redis.new(:driver => :synchrony)
            puts "kicking off a fiber for #{queue}"
            EM::Synchrony.sleep(1)
            happy = true
            while happy
              puts "everybody's happy"
              if self.jabber_connected
                puts "aparently jabber is connected..."
                events[queue] = redis.blpop(queue)
                event         = Yajl::Parser.parse(events[queue][1])
                type          = event['notification_type']
                entity, check = event['event_id'].split(':')
                state         = event['state']
                summary       = event['summary']
                self.go("#{type.upcase} ::: \"#{check}\" on #{entity} is #{state.upcase} ::: #{summary}")
              else
                puts "bugger, not connected, sleep 1 before retry"
                EM::Synchrony.sleep(1)
              end
            end
          end # FiberIterator do

          EM::Synchrony.add_periodic_timer(4) do
            puts "period timer after while loop"
          end

        end
      end

      def dispatch(notification)

        notification_type  = notification['notification_type']
        contact_first_name = notification['contact_first_name']
        contact_last_name  = notification['contact_last_name']
        state              = notification['state']
        summary            = notification['summary']
        time               = notification['time']
        entity, check      = notification['event_id'].split(':')

      end

    end
  end
end

