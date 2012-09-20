#!/usr/bin/env ruby

#require 'socket'

require 'eventmachine'
# the redis/synchrony gems need to be required in this particular order, see                                                # the redis-rb README for details
#require 'hiredis'
require 'em-synchrony'
#require 'redis/connection/synchrony'
#require 'redis'

#require 'chronic_duration'

require 'blather/client/client'
require 'em-synchrony/fiber_iterator'
require 'yajl/json_gem'

#require 'flapjack/data/entity_check'
require 'flapjack/pikelet'
require 'flapjack/utility'

module Flapjack

  class Oobetet < Blather::Client

    include Flapjack::Pikelet
    include Flapjack::Utility

    log = Logger.new(STDOUT)
    # log.level = Logger::DEBUG
    log.level = Logger::INFO
    Blather.logger = log

    def setup
      @hostname = Socket.gethostname
      @flapjacktest_jid = Blather::JID.new((@config['jabberid'] || 'flapjacktest') + "/#{@hostname}:#{Process.pid}")

      super(@flapjacktest_jid, @config['password'], @config['server'], @config['port'].to_i)

      logger.debug("Building jabber connection with jabberid: " +
        @flapjacktest_jid.to_s + ", port: " + @config['port'].to_s +
        ", server: " + @config['server'].to_s + ", password: " +
        @config['password'].to_s)

      @pagerduty_events_api_url = 'https://events.pagerduty.com/generic/2010-04-15/create_event.json'

      if !@config['watched_check'] or !@config['watched_entity']
        raise RuntimeError, 'Flapjack::Oobetet: watched_check and watched_entity must be defined in the config'
      end

      @check_matcher = '"' + @config['watched_check'] + '" on ' + @config['watched_entity']

      t = Time.now.to_i
      @times = { :last_problem  => t,
                 :last_recovery => t,
                 :last_ack      => t,
                 :last_ack_sent => t }

      @last_alert = nil

      register_handler :ready do |stanza|
        EM.next_tick do
          EM.synchrony do
            on_ready(stanza)
          end
        end
      end

      register_handler :message, :groupchat? do |stanza|
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
      @connected_at = Time.now.to_i
      logger.info("Jabber Connected")
      if @config['rooms'] && @config['rooms'].length > 0
        @config['rooms'].each do |room|
          logger.info("Joining room #{room}")
          presence = Blather::Stanza::Presence.new
          presence.from = @flapjacktest_jid
          presence.to = Blather::JID.new("#{room}/#{@config['alias']}")
          presence << "<x xmlns='http://jabber.org/protocol/muc'/>"
          write presence
          say(room, "flapjack self monitoring (oobetet) started at #{Time.now}, g'day!", :groupchat)
        end
      end
    end

    def on_groupchat(stanza)
      return if should_quit?
      logger.debug("groupchat stanza body: " + stanza.body)
      logger.debug("groupchat message received: #{stanza.inspect}")

      if stanza.body =~ /^(\w+).*#{Regexp.escape(@check_matcher)} is (\w+)/
        # got something interesting
        logger.debug("groupchat found the following state for #{@check_matcher}")
        case $1.downcase
        when 'problem'
          @times[:last_problem] = Time.new.to_i
        when 'recovery'
          @times[:last_recovery] = Time.new.to_i
        when 'acknowledgement'
          @times[:last_ack] = Time.new.to_i
        end

      end

    end

    def check_timers
      t = Time.new.to_i
      breach = nil
      case
      when @times[:last_problem]  > (t - 300)
        breach = "haven't seen a test problem notification in the last five minutes"
      when @times[:last_recovery] > (t - 300)
        breach = "haven't seen a test recovery notification in the last five minutes"
      end

      return unless breach
      @logger.error("Self monitoring has detected the following breach: #{breach}")
      summary = "Flapjack Self Monitoring is Critical: #{breach} for #{@check_matcher}, from #{@hostname} at #{Time.now}"

      if !@last_alert or @last_alert < (t - 55)

        if @config['rooms'] && @config['rooms'].length > 0
          @config['rooms'].each do |room|
            say(room, summary, :groupchat)
          end
        end

        if @config['jabber_contact']
          say(@config['jabber_contact'], summary)
          @last_alert = t
        end

        if @config['pagerduty_contact']
          pagerduty_event = { :service_key  => @config['pagerduty_contact'],
                              :incident_key => "Flapjack Self Monitoring from #{@hostname}",
                              :event_type   => 'trigger',
                              :description  => summary }
          send_pagerduty_event(pagerduty_event)
          @last_alert = t
        end

        if !@last_alert or @last_alert < (t - 55)
          @logger.error("NOTICE: Self monitoring has detected a failure and is unable to tell anyone about it")
        end

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

    def send_pagerduty_alert

    end

    def send_pagerduty_event(event)
      options  = { :body => Yajl::Encoder.encode(event) }
      http = EM::HttpRequest.new(@pagerduty_events_api_url).post(options)
      response = Yajl::Parser.parse(http.response)
      status   = http.response_header.status
      logger.debug "send_pagerduty_event got a return code of #{status.to_s} - #{response.inspect}"
      [status, response]
    end

    def main
      logger.debug("New oobetet pikelet with the following options: #{@config.inspect}")

      keepalive_timer = EM::Synchrony.add_periodic_timer(60) do
        logger.debug("calling keepalive on the jabber connection")
        write(' ') if connected?
      end

      check_timers_timer = EM::Synchrony.add_periodic_timer(10) do
        check_timers
      end

      setup
      connect # Blather::Client.connect

      if should_quit?
        keepalive_timer.cancel
        check_timers_timer.cancel
      end
    end

  end
end



