#!/usr/bin/env ruby

require 'socket'
require 'eventmachine'
require 'em-synchrony'
require 'blather/client/client'
require 'em-synchrony/fiber_iterator'
require 'yajl/json_gem'

require 'flapjack/utility'
require 'flapjack/gateways/base'

module Flapjack

  module Gateways

    class Oobetet < Blather::Client

      include Flapjack::Gateways::Generic
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
        @max_latency = @config['max_latency'] || 300
        @flapjack_ok = true

        t = Time.now.to_i
        @times = { :last_problem  => t,
                   :last_recovery => t,
                   :last_ack      => t,
                   :last_ack_sent => t }

        @last_alert = nil
      end

      # split out to ease testing
      def register_handlers
        register_handler :ready do |stanza|
          EventMachine::Synchrony.next_tick do
            on_ready(stanza)
          end
        end

        register_handler :message, :groupchat? do |stanza|
          EventMachine::Synchrony.next_tick do
            on_groupchat(stanza)
          end
        end

        register_handler :disconnected do |stanza|
          ret = true
          EventMachine::Synchrony.next_tick do
            ret = on_disconnect(stanza)
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

      # returning true to prevent the reactor loop from stopping
      def on_disconnect(stanza)
        return true if should_quit?
        logger.warn("jabbers disconnected! reconnecting in 1 second ...")
        EventMachine::Timer.new(1) do
          connect # Blather::Client.connect
        end
        true
      end

      def on_groupchat(stanza)
        return if should_quit?

        stanza_body = stanza.body

        logger.debug("groupchat stanza body: " + stanza_body)
        logger.debug("groupchat message received: #{stanza.inspect}")

        if (stanza_body =~ /^(?:problem|recovery|acknowledgement)/i) &&
           (stanza_body =~ /^(\w+).*#{Regexp.escape(@check_matcher)}/)

          # got something interesting
          status = $1.downcase
          t = Time.now.to_i
          logger.debug("groupchat found the following state for #{@check_matcher}: #{status}")

          case status
          when 'problem'
            logger.debug("updating @times last_problem")
            @times[:last_problem] = t
          when 'recovery'
            logger.debug("updating @times last_recovery")
            @times[:last_recovery] = t
          when 'acknowledgement'
            logger.debug("updating @times last_ack")
            @times[:last_ack] = t
          end
        end
        logger.debug("@times: #{@times.inspect}")
      end

      def check_timers
        t = Time.now.to_i
        breach = nil
        @logger.debug("check_timers: inspecting @times #{@times.inspect}")
        case
        when @times[:last_problem] < (t - @max_latency)
          breach = "haven't seen a test problem notification in the last #{@max_latency} seconds"
        when @times[:last_recovery] < (t - @max_latency)
          breach = "haven't seen a test recovery notification in the last #{@max_latency} seconds"
        end

        unless @flapjack_ok || breach
          emit_jabber("Flapjack Self Monitoring is OK")
          emit_pagerduty("Flapjack Self Monitoring is OK", 'resolve')
        end

        @flapjack_ok = !breach

        return unless breach
        @logger.error("Self monitoring has detected the following breach: #{breach}")
        summary  = "Flapjack Self Monitoring is Critical: #{breach} for #{@check_matcher}, "
        summary += "from #{@hostname} at #{Time.now}"

        if !@last_alert or @last_alert < (t - 55)

          emit_jabber(summary)
          emit_pagerduty(summary, 'trigger')

          if !@last_alert or @last_alert < (t - 55)
            msg  = "NOTICE: Self monitoring has detected a failure and is unable to tell "
            msg += "anyone about it. DON'T PANIC."
            @logger.error msg
          end

        end
      end

      def emit_jabber(summary)
        if @config['rooms'] && @config['rooms'].length > 0
          @config['rooms'].each do |room|
            say(room, summary, :groupchat)
          end
          @last_alert = Time.now.to_i
        end
      end

      def emit_pagerduty(summary, event_type = 'trigger')
        if @config['pagerduty_contact']
          pagerduty_event = { :service_key  => @config['pagerduty_contact'],
                              :incident_key => "Flapjack Self Monitoring from #{@hostname}",
                              :event_type   => event_type,
                              :description  => summary }
          status, response = send_pagerduty_event(pagerduty_event)
          if status == 200
            @logger.debug("successfully sent pagerduty event")
            @last_alert = Time.now.to_i
          else
            @logger.error("pagerduty returned #{status} #{response.inspect}")
          end
        end
      end

      def say(to, msg, using = :chat)
        @logger.debug("Sending a jabber message to: #{to.to_s}, using: #{using.to_s}, message: #{msg}")
        write Blather::Stanza::Message.new(to, msg, using)
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

        setup
        register_handlers
        connect # Blather::Client.connect

        until should_quit?
          EM::Synchrony.sleep(10)
          check_timers
        end

        keepalive_timer.cancel
      end

    end
  end
end



