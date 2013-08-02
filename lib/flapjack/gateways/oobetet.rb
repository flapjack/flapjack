#!/usr/bin/env ruby

require 'socket'
# require 'blather/client/dsl'
require 'oj'

require 'flapjack/utility'

module Flapjack

  module Gateways

    module Oobetet

      class Notifier

        PAGERDUTY_EVENTS_API_URL = 'https://events.pagerduty.com/generic/2010-04-15/create_event.json'

        def initialize(options = {})
          @config = options[:config]
          @logger = options[:logger]

          @hostname = Socket.gethostname

          unless @config['watched_check'] && @config['watched_entity']
            raise RuntimeError, 'Flapjack::Oobetet: watched_check and watched_entity must be defined in the config'
          end
          @check_matcher = '"' + @config['watched_check'] + '" on ' + @config['watched_entity']

          @flapjack_ok = true
          @last_alert = nil
        end

        def start

          loop do
            synchronize do
              check_timers
            end

            Kernel.sleep 10
          end
        rescue Flapjack::PikeletStop
          logger.info "finishing oobetet"
        end

        def stop(thread)
          synchronize do
            thread.raise Flapjack::PikeletStop.new
          end
        end

        private

        def check_timers
          t = Time.now.to_i
          breach = @bot.breach?(t)

          if @last_breach && !breach
            emit_jabber("Flapjack Self Monitoring is OK")
            emit_pagerduty("Flapjack Self Monitoring is OK", 'resolve')
          end

          return unless @last_breach = breach
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
          uri = URI::HTTP.build(:host => 'https://events.pagerduty.com',
                                :path => '/generic/2010-04-15/create_event.json')
          http = Net::HTTP.new(uri.host, uri.port)
          request = Net::HTTP::Post.new(uri.request_uri)
          request.body = Oj.dump(event)
          http_response = http.request(request)

          response = Oj.load(http_response.body)
          status   = http_response_header.code
          @logger.debug "send_pagerduty_event got a return code of #{status.to_s} - #{response.inspect}"
          [status, response]
        end

      end

      class TimeChecker

        include MonitorMixin

        def initialize(opts = {})
          @config = opts[:config]
          @logger = opts[:logger]

          mon_initialize

          @should_quit = false
          @shutdown_cond = new_cond

          @times = { :last_problem  => nil,
                     :last_recovery => nil,
                     :last_ack      => nil,
                     :last_ack_sent => nil }

          unless @config['watched_check'] && @config['watched_entity']
            raise RuntimeError, 'Flapjack::Oobetet: watched_check and watched_entity must be defined in the config'
          end
          @check_matcher = '"' + @config['watched_check'] + '" on ' + @config['watched_entity']
          @max_latency = @config['max_latency'] || 300

          @logger.debug("new oobetet pikelet with the following options: #{@config.inspect}")
        end

        def start
          synchronize do
            t = Time.now.to_i
            @times[:last_problem]  = t
            @times[:last_recovery] = t
            @times[:last_ack]      = t
            @times[:last_ack_sent] = t
            @shutdown_cond.wait_until { @should_quit }
          end
        end

        def stop(thread)
          synchronize do
            @should_quit = true
            @shutdown_cond.signal
          end
        end

        def received_message(room, nick, time, text)
          synchronize do
            @logger.debug("group message received: #{room}, #{text}")

            if (text =~ /^(?:problem|recovery|acknowledgement)/i) &&
               (text =~ /^(\w+).*#{Regexp.escape(@check_matcher)}/)

              # got something interesting
              status = $1.downcase
              t = Time.now.to_i
              @logger.debug("found the following state for #{@check_matcher}: #{status}")

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
        end

        def breach?(time)
          synchronize do
            @logger.debug("check_timers: inspecting @times #{@times.inspect}")
            if @times[:last_problem] < (time - @max_latency)
              "haven't seen a test problem notification in the last #{@max_latency} seconds"
            elsif @times[:last_recovery] < (time - @max_latency)
              "haven't seen a test recovery notification in the last #{@max_latency} seconds"
            end
          end
        end

      end

      class Bot

        include MonitorMixin
        include Flapjack::Utility

        attr_accessor :siblings

        def initialize(opts = {})
          @config = opts[:config]
          @logger = opts[:logger]

          @hostname = Socket.gethostname

          mon_initialize

          @should_quit = false
          @shutdown_cond = new_cond

      #     unless @config['watched_check'] && @config['watched_entity']
      #       raise RuntimeError, 'Flapjack::Oobetet: watched_check and watched_entity must be defined in the config'
      #     end
      #     @check_matcher = '"' + @config['watched_check'] + '" on ' + @config['watched_entity']
      #     @max_latency = @config['max_latency'] || 300

          @logger.debug("new oobetet pikelet with the following options: #{@config.inspect}")
        end

        def start
          synchronize do

            @logger.info("starting")

            # ::Jabber::debug = true

            jabber_id = @config['jabberid'] || 'flapjack'

            @flapjack_jid = ::Jabber::JID.new(jabber_id + '/' + @hostname)
            @client = ::Jabber::Client.new(@flapjack_jid)

            @muc_clients = @config['rooms'].inject({}) do |memo, room|
              muc_client = ::Jabber::MUC::SimpleMUCClient.new(@client)
              memo[room] = muc_client
              memo
            end

            @client.connect
            @client.auth(@config['password'])
            @client.send(::Jabber::Presence.new.set_type(:available))

            @muc_clients.each_pair do |room, muc_client|
              muc_client.on_message do |time, nick, text|
                next if nick == jabber_id

                if @time_checker
                  @time_checker.received_message(room, nick, time, text)
                end
              end

              muc_client.join(room + '/' + @config['alias'])
              muc_client.say("flapjack oobetet gateway started at #{Time.now}, hello!")
            end

            # block this thread until signalled to quit
            @shutdown_cond.wait_until { @should_quit }

            @muc_clients.each_pair do |room, muc_client|
              muc_client.exit if muc_client.active?
            end

            @client.close
          end
        end

        def stop
          synchronize do
            @should_quit = true
            @shutdown_cond.signal
          end
        end

        # TODO buffer if room not connected?
        def announce(room, msg)
          synchronize do
            unless @muc_clients.empty?
              if muc_client = @muc_clients[room]
                muc_client.say(msg)
              end
            end
          end
        end

      end

    end
  end
end
