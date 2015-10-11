#!/usr/bin/env ruby

require 'net/http'
require 'socket'
require 'uri'
require 'uri/https'

require 'xmpp4r'
require 'xmpp4r/muc/helper/simplemucclient'

require 'flapjack/exceptions'
require 'flapjack/utility'

module Flapjack

  module Gateways

    module Oobetet

      class Notifier

        attr_accessor :siblings

        def initialize(options = {})
          @lock = options[:lock]
          @config = options[:config]

          @hostname = Socket.gethostname

          unless @config['watched_check']
            raise RuntimeError, 'Flapjack::Oobetet: watched_check must be defined in the config'
          end
          @check_matcher = '"' + @config['watched_check'] + '"'

          @flapjack_ok = true
          @last_alert = nil
          @last_breach = nil
        end

        def start
          loop do
            @lock.synchronize do
              check_timers
            end

            Kernel.sleep 10
          end
        end

        def stop_type
          :exception
        end

        private

        def check_timers
          if @siblings
            @time_checker ||= @siblings.detect {|sib| sib.respond_to?(:breach?) }
            @bot ||= @siblings.detect {|sib| sib.respond_to?(:announce) }
          end

          t = Time.now
          breach = @time_checker.breach?(t) if @time_checker

          if @last_breach && !breach
            emit_jabber("Flapjack Self Monitoring is OK")
            emit_pagerduty("Flapjack Self Monitoring is OK", 'resolve')
          end

          @last_breach = breach
          return unless breach

          Flapjack.logger.error("Self monitoring has detected the following breach: #{breach}")
          summary = "Flapjack Self Monitoring is Critical: #{breach} for #{@check_matcher}, " +
                    "from #{@hostname} at #{t}"

          if @last_alert.nil? || @last_alert < (t.to_i - 55)

            announced_jabber    = emit_jabber(summary)
            announced_pagerduty = emit_pagerduty(summary, 'trigger')

            @last_alert = t.to_i if announced_jabber || announced_pagerduty

            if @last_alert.nil? || @last_alert < (t.to_i - 55)
              msg = "NOTICE: Self monitoring has detected a failure and is unable to tell " +
                    "anyone about it. DON'T PANIC."
              Flapjack.logger.error msg
            end
          end
        end

        def emit_jabber(summary)
          return if @bot.nil?
          @bot.announce(summary)
          true
        end

        def emit_pagerduty(summary, event_type = 'trigger')
          return if @config['pagerduty_contact'].nil?
          status, response = send_pagerduty_event(:service_key  => @config['pagerduty_contact'],
                                                  :incident_key => "Flapjack Self Monitoring from #{@hostname}",
                                                  :event_type   => event_type,
                                                  :description  => summary)
          unless '200'.eql?(status)
            Flapjack.logger.error("pagerduty returned #{status} #{response.inspect}")
            return false
          end

          Flapjack.logger.debug("successfully sent pagerduty event")
          true
        end

        # TODO trap Oj JSON errors
        # FIXME common code with the pagerduty gateway, move to shared module
        def send_pagerduty_event(opts = {})
          event = { 'service_key'  => opts[:service_key],
                    'incident_key' => opts[:incident_key],
                    'event_type'   => opts[:event_type],
                    'description'  => opts[:description] }

          uri = URI::HTTPS.build(:host => 'events.pagerduty.com',
                                 :path => '/generic/2010-04-15/create_event.json',
                                 :port => 443)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
          request = Net::HTTP::Post.new(uri.request_uri)
          request.body = Flapjack.dump_json(event)
          http_response = http.request(request)

          response = Flapjack.load_json(http_response.body)
          status   = http_response.code
          Flapjack.logger.debug "send_pagerduty_event got a return code of #{status} - #{response.inspect}"
          [status, response]
        end

      end

      class TimeChecker

        def initialize(opts = {})
          @lock   = opts[:lock]
          @stop_cond = opts[:stop_condition]
          @config = opts[:config]

          @max_latency = @config['max_latency'] || 300

          @times = { :last_problem  => nil,
                     :last_recovery => nil,
                     :last_ack      => nil,
                     :last_ack_sent => nil }

          Flapjack.logger.debug("new oobetet pikelet with the following options: #{@config.inspect}")
        end

        def start
          @lock.synchronize do
            t = Time.now.to_i
            @times[:last_problem]  = t
            @times[:last_recovery] = t
            @times[:last_ack]      = t
            @times[:last_ack_sent] = t
            @stop_cond.wait_until { @should_quit }
          end
        end

        def stop_type
          :signal
        end

        def receive_status(status, time)
          @lock.synchronize do
            case status
            when 'problem'
              Flapjack.logger.debug("updating @times last_problem")
              @times[:last_problem] = time
            when 'recovery'
              Flapjack.logger.debug("updating @times last_recovery")
              @times[:last_recovery] = time
            when 'acknowledgement'
              Flapjack.logger.debug("updating @times last_ack")
              @times[:last_ack] = time
            end
            Flapjack.logger.debug("@times: #{@times.inspect}")
          end
        end

        def breach?(time)
          @lock.synchronize do
            Flapjack.logger.debug("check_timers: inspecting @times #{@times.inspect}")
            if @times[:last_problem] < (time - @max_latency)
              "haven't seen a test problem notification in the last #{@max_latency} seconds"
            elsif @times[:last_recovery] < (time - @max_latency)
              "haven't seen a test recovery notification in the last #{@max_latency} seconds"
            end
          end
        end

      end

      class Bot

        include Flapjack::Utility

        attr_accessor :siblings

        def initialize(opts = {})
          @lock = opts[:lock]
          @stop_cond = opts[:stop_condition]
          @config = opts[:config]

          @hostname = Socket.gethostname

          unless @config['watched_check']
            raise RuntimeError, 'Flapjack::Oobetet: watched_check must be defined in the config'
          end
          @check_matcher = '"' + @config['watched_check'] + '"'

          Flapjack.logger.debug("new oobetet pikelet with the following options: #{@config.inspect}")
        end

        def start
          @lock.synchronize do
            @time_checker ||= @siblings && @siblings.detect {|sib| sib.respond_to?(:receive_status) }

            Flapjack.logger.info("starting")

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
                  Flapjack.logger.debug("group message received: #{room}, #{text}")
                  if (text =~ /^((?i:problem|recovery|acknowledgement)).*#{Regexp.escape(@check_matcher)}/)
                    # got something interesting
                    status = Regexp.last_match(1).downcase
                    Flapjack.logger.debug("found the following state for #{@check_matcher}: #{status}")
                    @time_checker.receive_status(status, time.to_i)
                  end
                end
              end

              muc_client.join(room + '/' + @config['alias'])
              muc_client.say("flapjack oobetet gateway started at #{Time.now}, hello!")
            end

            # block this thread until signalled to quit
            @stop_cond.wait_until { @should_quit }

            @muc_clients.each_pair do |room, muc_client|
              muc_client.exit if muc_client.active?
            end

            @client.close
          end
        end

        def stop_type
          :signal
        end

        # TODO buffer if not connected?
        def announce(msg)
          @lock.synchronize do
            unless @muc_clients.empty?
              @muc_clients.each_pair do |room, muc_client|
                muc_client.say(msg)
              end
            end
          end
        end

      end

    end
  end
end
