#!/usr/bin/env ruby

require 'socket'
require 'eventmachine'
require 'blather/client/dsl'
require 'oj'

require 'flapjack/utility'

module Flapjack

  module Gateways

    module Oobetet

      class Notifier

        PAGERDUTY_EVENTS_API_URL = 'https://events.pagerduty.com/generic/2010-04-15/create_event.json'

        def self.pikelet_settings
          {:em_synchrony => false,
           :em_stop      => true}
        end

        def initialize(options = {})
          @config = options[:config]
          @logger = options[:logger]

          if options[:siblings]
            # only works because the bot instance was initialised already (and
            # the siblings array was transformed via map(&:pikelet))
            # TODO clean up the sibling code so that it would work in
            # either arrangement
            @bot = options[:siblings].first
          end

          unless @config['watched_check'] && @config['watched_entity']
            raise RuntimeError, 'Flapjack::Oobetet: watched_check and watched_entity must be defined in the config'
          end
          @check_matcher = '"' + @config['watched_check'] + '" on ' + @config['watched_entity']

          @flapjack_ok = true
          @last_alert = nil
        end

        def stop
          # TODO synchronize access to @should_quit
          @should_quit = true
          @check_timer.cancel
        end

        def start
           @check_timer = EM.add_periodic_timer(10) { check_timers }
        end

        private

        def check_timers
          t = Time.now.to_i
          breach = @bot.breach?(t)

          unless @flapjack_ok || breach
            emit_jabber("Flapjack Self Monitoring is OK")
            emit_pagerduty("Flapjack Self Monitoring is OK", 'resolve')
          end

          @flapjack_ok = !breach

          return unless breach
          @logger.error("Self monitoring has detected the following breach: #{breach}")
          summary = "Flapjack Self Monitoring is Critical: #{breach} for #{@check_matcher}, " +
                    "from #{@hostname} at #{Time.now}"

          if !@last_alert || @last_alert < (t - 55)

            announced_jabber    = emit_jabber(summary)
            announced_pagerduty = emit_pagerduty(summary, 'trigger')

            @last_alert = Time.now.to_i if announced_jabber || announced_pagerduty

            if !@last_alert || @last_alert < (t - 55)
              msg = "NOTICE: Self monitoring has detected a failure and is unable to tell " +
                    "anyone about it. DON'T PANIC."
              @logger.error msg
            end
          end
        end

        def emit_jabber(summary)
          return false unless @bot
          @bot.announce(summary)
          true
        end

        def emit_pagerduty(summary, event_type = 'trigger')
          return false if @config['pagerduty_contact']
          pagerduty_event = { :service_key  => @config['pagerduty_contact'],
                              :incident_key => "Flapjack Self Monitoring from #{@hostname}",
                              :event_type   => event_type,
                              :description  => summary }
          status, response = send_pagerduty_event(pagerduty_event)
          if status != 200
            @logger.error("pagerduty returned #{status} #{response.inspect}")
            return false
          end

          @logger.debug("successfully sent pagerduty event")
          true
        end

        def send_pagerduty_event(event)
          options  = { :body => Oj.dump(event) }
          http = EventMachine::HttpRequest.new(PAGERDUTY_EVENTS_API_URL).post(options)
          response = Oj.load(http.response)
          status   = http.response_header.status
          @logger.debug "send_pagerduty_event got a return code of #{status.to_s} - #{response.inspect}"
          [status, response]
        end

      end

      class BotClient
        include Blather::DSL
      end

      # TODO synchronisation, buffering text

      class Bot
        include Flapjack::Utility

        log = ::Logger.new(STDOUT)
        # log.level = ::Logger::DEBUG
        log.level = ::Logger::INFO
        Blather.logger = log

        def self.pikelet_settings
          {:em_synchrony => false,
           :em_stop      => false}
        end

        def initialize(opts = {})
          @config = opts[:config]
          @logger = opts[:logger]

          unless @config['watched_check'] && @config['watched_entity']
            raise RuntimeError, 'Flapjack::Oobetet: watched_check and watched_entity must be defined in the config'
          end
          @check_matcher = '"' + @config['watched_check'] + '" on ' + @config['watched_entity']
          @max_latency = @config['max_latency'] || 300

          @monitor = Monitor.new

          @buffer = []
          @hostname = Socket.gethostname
          @times = { :last_problem  => nil,
                     :last_recovery => nil,
                     :last_ack      => nil,
                     :last_ack_sent => nil }
        end

        def start
          @logger.debug("New oobetet pikelet with the following options: #{@config.inspect}")

          @bot_thread = Thread.current

          @flapjack_jid = ::Blather::JID.new((@config['jabberid'] || 'flapjacktest') + "/#{@hostname}:#{Process.pid}")

          @client = Flapjack::Gateways::Oobetet::BotClient.new
          @client.setup(@flapjack_jid, @config['password'], @config['server'],
                        @config['port'].to_i)

          @logger.debug("Building jabber connection with jabberid: " +
            @flapjack_jid.to_s + ", port: " + @config['port'].to_s +
            ", server: " + @config['server'].to_s + ", password: " +
            @config['password'].to_s)

          # need direct access to the real blather client to mangle the handlers
          blather_client = @client.send(:client)
          blather_client.clear_handlers :error
          blather_client.register_handler :error do |err|
            @logger.warn(err.message)
          end

          @client.when_ready do |stanza|
            on_ready(stanza)
          end

          @client.message :groupchat? do |stanza|
            on_groupchat(stanza)
          end

          @client.disconnected do |stanza|
            on_disconnect(stanza)
          end

          t = Time.now.to_i
          @times[:last_problem]  = t
          @times[:last_recovery] = t
          @times[:last_ack]      = t
          @times[:last_ack_sent] = t

          @client.run
        end

        def stop
          synced do
            @should_quit = true
            @client.shutdown if @connected
          end

          # without this eventmachine in the bot thread seems to wait for
          # an event of some sort (network activity, or a timer firing)
          # before it realises that it has finished.
          # (should maybe use @bot_thread.wakeup instead)
          @bot_thread.run if @bot_thread.alive?
        end

        def synced(&block)
          ret = nil
          @monitor.synchronize { ret = block.call }
          ret
        end

        def breach?(time)
          @logger.debug("check_timers: inspecting @times #{@times.inspect}")
          if @times[:last_problem] < (time - @max_latency)
            "haven't seen a test problem notification in the last #{@max_latency} seconds"
          elsif @times[:last_recovery] < (time - @max_latency)
            "haven't seen a test recovery notification in the last #{@max_latency} seconds"
          end
        end

        # Join the MUC Chat room after connecting.
        def on_ready(stanza)
          return if @should_quit
          @connected_at = Time.now.to_i
          @logger.info("Jabber Connected")

          @keepalive_timer = EM.add_periodic_timer(60) do
            @logger.debug("calling keepalive on the jabber connection")
            if @client.connected?
              @client.write(' ')
            end
          end

          if @config['rooms'] && @config['rooms'].length > 0
            @config['rooms'].each do |room|
              @logger.info("Joining room #{room}")
              presence = Blather::Stanza::Presence.new
              presence.from = @flapjacktest_jid
              presence.to = Blather::JID.new("#{room}/#{@config['alias']}")
              presence << "<x xmlns='http://jabber.org/protocol/muc'/>"
              @client.write_to_stream presence
              say(room, "flapjack self monitoring (oobetet) started at #{Time.now}, g'day!", :groupchat)
            end
          end
          synced do
            @connected = true
          end
          return if @buffer.empty?
          while buffered = @buffer.shift
            @logger.debug("Sending a buffered jabber message to: #{buffered[0]}, using: #{buffered[2]}, message: #{buffered[1]}")
            say(*buffered)
          end
        end

        # may return true to prevent the reactor loop from stopping
        def on_disconnect(stanza)
          @logger.warn("disconnect handler called")
          @keepalive_timer.cancel unless @keepalive_timer.nil?
          @keepalive_timer = nil
          return false if sq = synced { @connected = false; @should_quit }
          @logger.warn("jabbers disconnected! reconnecting after a short delay...")
          EventMachine::Timer.new(1) do
            @client.run
          end
          true
        end

        def on_groupchat(stanza)
          return if @should_quit

          stanza_body = stanza.body

          @logger.debug("groupchat stanza body: #{stanza_body}")
          @logger.debug("groupchat message received: #{stanza.inspect}")

          if (stanza_body =~ /^(?:problem|recovery|acknowledgement)/i) &&
             (stanza_body =~ /^(\w+).*#{Regexp.escape(@check_matcher)}/)

            # got something interesting
            status = $1.downcase
            t = Time.now.to_i
            @logger.debug("groupchat found the following state for #{@check_matcher}: #{status}")

            case status
            when 'problem'
              @logger.debug("updating @times last_problem")
              @times[:last_problem] = t
            when 'recovery'
              @logger.debug("updating @times last_recovery")
              @times[:last_recovery] = t
            when 'acknowledgement'
              @logger.debug("updating @times last_ack")
              @times[:last_ack] = t
            end
          end
          @logger.debug("@times: #{@times.inspect}")
        end

        def announce(msg)
          if @config['rooms'] && @config['rooms'].length > 0
            @config['rooms'].each do |room|
              @logger.debug("Sending a jabber message to: #{room}, using: :groupchat, message: #{msg}")
              @client.write Blather::Stanza::Message.new(room, msg, :groupchat)
              say(room, msg, :groupchat)
            end
          end
        end

        def say(to, msg, using = :chat)
          if synced { @connected }
            @logger.debug("Sending a jabber message to: #{to.to_s}, using: #{using.to_s}, message: #{msg}")
            @client.say(to, msg, using)
          else
            @logger.debug("Buffering a jabber message to: #{to.to_s}, using: #{using.to_s}, message: #{msg}")
            @buffer << [to, msg, using]
          end
        end

      end

    end
  end
end
