#!/usr/bin/env ruby

require 'monitor'
require 'socket'

require 'chronic_duration'
require 'rexml/document'
require 'xmpp4r/query'
require 'xmpp4r/muc'

require 'flapjack/redis_proxy'
require 'flapjack/record_queue'
require 'flapjack/utility'
require 'flapjack/exceptions'
require 'flapjack/version'

require 'flapjack/data/alert'
require 'flapjack/data/check'
require 'flapjack/data/event'
require 'flapjack/data/scheduled_maintenance'
require 'flapjack/data/unscheduled_maintenance'
require 'flapjack/data/tag'


module Flapjack

  module Gateways

    module Jabber

      class Notifier

        include Flapjack::Utility

        attr_accessor :siblings

        def initialize(options = {})
          @lock = options[:lock]
          @config = options[:config]

          # TODO support for config reloading
          @queue = Flapjack::RecordQueue.new(@config['queue'] || 'jabber_notifications',
                     Flapjack::Data::Alert)
        end

        def start
          begin
            Zermelo.redis = Flapjack.redis

            loop do
              @lock.synchronize do
                @queue.foreach {|alert| handle_alert(alert) }
              end

              @queue.wait
            end
          ensure
            Flapjack.redis.quit
          end
        end

        def stop_type
          :exception
        end

        private

        def handle_alert(alert)
          @bot ||= @siblings && @siblings.detect {|sib| sib.respond_to?(:announce) }

          if @bot.nil?
            Flapjack.logger.warn("jabber bot not running, won't announce")
            return
          end

          check = alert.check
          check_name = check.name

          address = alert.address
          state = alert.state

          Flapjack.logger.debug("processing jabber notification address: #{address}, " +
                        "check: '#{check_name}', state: #{state}, summary: #{alert.summary}")

          # event_count = alert.event_count

          @ack_str = if state.eql?('ok') || ['test', 'acknowledgement'].include?(alert.type)
            nil
          else
            "#{@bot.alias}: ACKID #{alert.event_hash}"
          end

          message_type = alert.rollup ? 'rollup' : 'alert'

          message_template_erb, message_template =
            load_template(@config['templates'], message_type,
              'text', File.join(File.dirname(__FILE__), 'jabber'))

          @alert = alert
          bnd = binding

          message = nil
          begin
            message = message_template_erb.result(bnd).chomp
          rescue
            Flapjack.logger.error "Error while executing the ERB for a jabber message, " +
              "ERB being executed: #{message_template}"
            raise
          end

          # FIXME: should also check if presence has been established in any group chat rooms that are
          # configured before starting to process events, otherwise the first few may get lost (send
          # before joining the group chat rooms)
          @bot.announce(address, message)
        end

      end

      class Interpreter

        CHECK_MATCH_FRAGMENT = "(?:checks\s+(?:matching\s+\/(.+?)\/|with\s+tag\s+(.+?))|(.+?))"

        attr_accessor :siblings

        include Flapjack::Utility

        def initialize(opts = {})
          @lock = opts[:lock]
          @stop_cond = opts[:stop_condition]
          @config = opts[:config]

          @boot_time = opts[:boot_time]

          @should_quit = false

          @messages = []
        end

        def start
          Zermelo.redis = Flapjack.redis

          @lock.synchronize do

            @bot = self.siblings ? self.siblings.detect {|sib| sib.respond_to?(:announce)} : nil

            until @messages.empty? && @should_quit
              while msg = @messages.pop
                Flapjack.logger.info "interpreter received #{msg.inspect}"
                interpret(msg[:room], msg[:nick], msg[:time], msg[:message])
              end
              @stop_cond.wait_while { @messages.empty? && !@should_quit }
            end
          end
          Flapjack.redis.quit
        end

        def stop_type
          :signal
        end

        def receive_message(room, nick, time, msg)
          @lock.synchronize do
            @messages += [{:room => room, :nick => nick, :time => time, :message => msg}]
            @stop_cond.signal
          end
        end

        def get_check_details(check, at_time)
          start_range = Zermelo::Filters::IndexRange.new(nil, at_time, :by_score => true)
          end_range   = Zermelo::Filters::IndexRange.new(at_time, nil, :by_score => true)

          sched = check.scheduled_maintenances.intersect(:start_time => start_range,
                    :end_time => end_range).all.max_by(&:end_time)

          unsched = check.unscheduled_maintenances.intersect(:start_time => start_range,
                    :end_time => end_range).all.max_by(&:end_time)

          out = ''

          if sched.nil? && unsched.nil?
            out += "Not in scheduled or unscheduled maintenance.\n"
          else
            if sched.nil?
              out += "Not in scheduled maintenance.\n"
            else
              remain = time_period_in_words( (sched.end_time - at_time).ceil )
              # TODO a simpler time format?
              out += "In scheduled maintenance: #{sched.start_time} -> #{sched.end_time} (#{remain} remaining)\n"
            end

            if unsched.nil?
              out += "Not in unscheduled maintenance.\n"
            else
              remain = time_period_in_words( (unsched.end_time - at_time).ceil )
              # TODO a simpler time format?
              out += "In unscheduled maintenance: #{unsched.start_time} -> #{unsched.end_time} (#{remain} remaining)\n"
            end
          end

          out
        end

        def derive_check_ids_for(pattern, tag_name, check_name, options = {})
          lock_klasses = options[:lock_klasses] || []

          deriver = if !pattern.nil? && !pattern.strip.empty?
            proc {
              checks = begin
                Flapjack::Data::Check.intersect(:name => Regexp.new(pattern.strip))
              rescue RegexpError
                nil
              end

              if checks.nil?
                "Error parsing /#{pattern.strip}/"
              else
                num_checks = checks.count
                if num_checks == 0
                  "No checks match /#{pattern.strip}/"
                else
                  checks = checks.sort(:name, :limit => options[:limit]) if options[:limit]
                  yield(checks.ids, "matching /#{pattern.strip}/", num_checks) if block_given?
                end
              end
            }
          elsif !tag_name.nil? && !tag_name.strip.empty?

            lock_klasses.unshift(Flapjack::Data::Tag)

            proc {
              tag = Flapjack::Data::Tag.intersect(:name => tag_name.strip).all.first

              if tag.nil?
                "No tag '#{tag_name.strip}'"
              else
                checks = tag.checks
                num_checks = checks.count
                if num_checks == 0
                  "No checks with tag '#{tag_name.strip}'"
                else
                  checks = checks.sort(:name, :limit => options[:limit]) if options[:limit]
                  yield(checks.ids, "with tag '#{tag_name}'", num_checks) if block_given?
                end
              end
            }
          elsif !check_name.nil? && !check_name.strip.empty?
            proc {
              checks = Flapjack::Data::Check.intersect(:name => check_name.strip)

              if checks.empty?
                "No check exists with name '#{check_name.strip}'"
              else
                num_checks = checks.count
                checks = checks.sort(:name, :limit => options[:limit]) if options[:limit]
                yield(checks.ids, "with name '#{check_name.strip}'", num_checks) if block_given?
              end
            }
          end

          return if deriver.nil?

          if lock_klasses.empty?
            Flapjack::Data::Check.lock(&deriver)
          else
            Flapjack::Data::Check.lock(*lock_klasses, &deriver)
          end
        end

        def interpret(room, nick, time, command)
          msg = nil
          action = nil
          check = nil

          begin
            case command
            when /^help\s*$/
              msg = "commands: \n" +
                    "  find (number) checks matching /pattern/\n" +
                    "  find (number) checks with tag <tag>\n" +
                    "  state of <check>\n" +
                    "  state of checks matching /pattern/\n" +
                    "  state of checks with tag <tag>\n" +
                    "  tell me about <check>\n" +
                    "  tell me about (number) checks matching /pattern/\n" +
                    "  tell me about (number) checks with tag <tag>\n" +
                    "  ACKID <id>[ duration: <time spec>][ comment: <comment>]\n" +
                    "  ack <check>[ duration: <time spec>][ comment: <comment>]\n" +
                    "  ack checks matching /pattern/[ duration: <time spec>][ comment: <comment>]\n" +
                    "  ack checks with tag <tag>[ duration: <time spec>][ comment: <comment>]\n" +
                    "  maint <check>[ (start-at|start-in): <time spec>][ duration: <time spec>][ comment: <comment>]\n" +
                    "  maint checks matching /pattern/[ (start-at|start-in): <time spec>][ duration: <time spec>][ comment: <comment>]\n" +
                    "  maint checks with tag <tag>[ (start-at|start-in): <time spec>][ duration: <time spec>][ comment: <comment>]\n" +
                    "  test notifications for <check>\n" +
                    "  test notifications for checks matching /pattern/\n" +
                    "  test notifications for checks with tag <tag>\n" +
                    "  identify\n" +
                    "  help\n"

            when /^identify\s*$/
              t    = Process.times
              fqdn = `/bin/hostname -f`.chomp
              pid  = Process.pid
              msg  = "Flapjack #{Flapjack::VERSION} process #{pid} on #{fqdn} \n" +
                     "Identifiers: #{@bot.identifiers.join(', ')}\n" +
                     "Boot time: #{@boot_time}\n" +
                     "User CPU Time: #{t.utime}\n" +
                     "System CPU Time: #{t.stime}\n" +
                     `uname -a`.chomp + "\n"

            when /^find\s+(\d+\s+)?checks\s+(?:matching\s+\/(.+)\/|with\s+tag\s+(.+))\s*$/im
              limit_checks = Regexp.last_match(1).nil? ? 30 : Regexp.last_match(1).strip.to_i
              pattern     = Regexp.last_match(2)
              tag         = Regexp.last_match(3)

              msg = derive_check_ids_for(pattern, tag, nil, :limit => limit_checks) do |check_ids, descriptor, num_checks|
                resp = "Checks #{descriptor}:\n"
                checks = Flapjack::Data::Check.find_by_ids(*check_ids)
                resp += "Showing first #{limit_checks} results of #{num_checks}:\n" if num_checks > limit_checks
                resp += checks.map {|chk|
                  cond = chk.condition
                  "#{chk.name} is #{cond.nil? ? '[none]' : cond.upcase}"
                }.join(', ')
                resp
              end

            when /^state\s+of\s+#{CHECK_MATCH_FRAGMENT}\s*$/im
              pattern    = Regexp.last_match(1)
              tag        = Regexp.last_match(2)
              check_name = Regexp.last_match(3)

              msg = derive_check_ids_for(pattern, tag, check_name) do |check_ids, descriptor|
                "State of checks #{descriptor}:\n" +
                  Flapjack::Data::Check.intersect(:id => check_ids).collect {|chk|
                    cond = chk.condition
                    "#{chk.name} - #{cond.nil? ? '[none]' : cond.upcase}"
                  }.join("\n")
              end

            when /^tell\s+me\s+about\s(\d+\s+)?+#{CHECK_MATCH_FRAGMENT}\s*$/im
              limit_checks = Regexp.last_match(1).nil? ? 30 : Regexp.last_match(1).strip.to_i
              pattern      = Regexp.last_match(2)
              tag          = Regexp.last_match(3)
              check_name   = Regexp.last_match(4)

              msg = derive_check_ids_for(pattern, tag, check_name, :limit => limit_checks,
                      :lock_klasses => [Flapjack::Data::ScheduledMaintenance,
                                        Flapjack::Data::UnscheduledMaintenance]) do |check_ids, descriptor, num_checks|
                current_time = Time.now
                resp = "Details of checks #{descriptor}\n"
                resp += "Showing first #{limit_checks} results of #{num_checks}:\n" if num_checks > limit_checks
                resp += Flapjack::Data::Check.intersect(:id => check_ids).collect {|chk|
                          get_check_details(chk, current_time)
                        }.join("")
              end

            when /^ACKID\s+([0-9A-F]+)(?:\s*(.*?)(?:\s*duration:.*?(\w+.*))?)$/im
              ackid        = Regexp.last_match(1)
              comment      = Regexp.last_match(2)
              duration_str = Regexp.last_match(3)

              error = nil
              dur   = nil

              if comment.nil? || (comment.length == 0)
                error = "please provide a comment, eg \"#{@bot.alias}: ACKID #{Regexp.last_match(1)} AL looking\""
              elsif duration_str
                # a fairly liberal match above, we'll let chronic_duration do the heavy lifting
                dur = ChronicDuration.parse(duration_str)
              end

              four_hours = 4 * 60 * 60
              duration = (dur.nil? || (dur <= 0)) ? four_hours : dur

              check = Flapjack::Data::Check.intersect(:ack_hash => ackid).all.first

              if check.nil?
                msg = "ERROR - couldn't ACK #{ackid} - not found"
              else
                check_name = check.name

                details = "#{check_name} (#{ackid})"
                if check.in_unscheduled_maintenance?
                  msg = "Changing ACK for #{details}"
                else
                  msg = "ACKing #{details}"
                end

                action = Proc.new {
                  Flapjack::Data::Event.create_acknowledgements(
                    @config['processor_queue'] || 'events',
                    [check],
                    :summary => (comment || ''),
                    :acknowledgement_id => ackid,
                    :duration => duration,
                  )
                }
              end

            when /^ack\s+#{CHECK_MATCH_FRAGMENT}(?:\s+(.*?)(?:\s*duration:.*?(\w+.*))?)?\s*$/im
              pattern      = Regexp.last_match(1)
              tag          = Regexp.last_match(2)
              check_name   = Regexp.last_match(3)
              comment      = Regexp.last_match(4) ? Regexp.last_match(4).strip : nil
              duration_str = Regexp.last_match(5) ? Regexp.last_match(5).strip : '1 hour'
              duration     = ChronicDuration.parse(duration_str)

              msg = derive_check_ids_for(pattern, tag, check_name,
                      :lock_klasses => [Flapjack::Data::UnscheduledMaintenance]) do |check_ids, descriptor|

                failing_checks = Flapjack::Data::Check.
                  intersect(:id => check_ids, :failing => true)

                if failing_checks.empty?
                  "No failing checks #{descriptor}"
                else
                  summary = "#{nick}: #{comment.blank? ? 'Set via chatbot' : comment}"

                  action = Proc.new {
                    Flapjack::Data::Event.create_acknowledgements(
                      @config['processor_queue'] || 'events',
                      failing_checks,
                      :summary  => summary,
                      :duration => duration
                    )
                  }

                  "Ack list:\n" + failing_checks.map(&:name).join("\n")
                end
              end

            when /^maint\s+#{CHECK_MATCH_FRAGMENT}\s+(?:start-in:.*?(\w+.*?)|start-at:.*?(\w+.*?))?(?:\s+duration:.*?(\w+.*?))?(?:\s+comment:.*?(\w+.*?))?\s*$/im
              pattern      = Regexp.last_match(1)
              tag          = Regexp.last_match(2)
              check_name   = Regexp.last_match(3)
              start_in     = Regexp.last_match(4) ? Regexp.last_match(4).strip : nil
              start_at     = Regexp.last_match(5) ? Regexp.last_match(5).strip : nil
              duration_str = Regexp.last_match(6) ? Regexp.last_match(6).strip : '1 hour'
              duration     = ChronicDuration.parse(duration_str)
              comment      = Regexp.last_match(7) ? Regexp.last_match(7).strip : 'Test maintenance'

              started = case
              when start_in
                Time.now.to_i + ChronicDuration.parse(start_in)
              when start_at
                Chronic.parse(start_at).to_i
              else
                Time.now.to_i
              end

              msg = derive_check_ids_for(pattern, tag, check_name,
                      :lock_klasses => [Flapjack::Data::ScheduledMaintenance]) do |check_ids, descriptor|
                checks = Flapjack::Data::Check.find_by_ids(*check_ids)

                checks.each do |chk|
                  sched_maint = Flapjack::Data::ScheduledMaintenance.new(
                    :start_time => started,
                    :end_time   => started + duration,
                    :summary    => comment
                  )
                  sched_maint.save

                  chk.scheduled_maintenances << sched_maint
                end

                "Scheduled maintenance for #{duration/60} minutes starting at #{Time.at(started)} on:\n" + checks.collect {|c| "#{c.name}" }.join("\n")
              end

            when /^test\s+notifications\s+for\s+#{CHECK_MATCH_FRAGMENT}\s*$/im
              pattern    = Regexp.last_match(1)
              tag        = Regexp.last_match(2)
              check_name = Regexp.last_match(3)

              msg = derive_check_ids_for(pattern, tag, check_name) do |check_ids, descriptor|
                summary = "Testing notifications to all contacts interested in checks #{descriptor}"

                checks = Flapjack::Data::Check.find_by_ids(*check_ids)

                action = Proc.new {
                  Flapjack::Data::Event.test_notifications(@config['processor_queue'] || 'events',
                    checks, :summary => summary)
                }
                "Testing notifications for check#{(checks.size > 1) ? 's' : ''} #{descriptor}"
              end

            when /^(.*)/
              words = Regexp.last_match(1)
              msg   = "what do you mean, '#{words}'? Type 'help' for a list of acceptable commands."

            end

          rescue => e
            Flapjack.logger.error { "Exception when interpreting command '#{command}' - #{e.class}, #{e.message}" }
            Flapjack.logger.debug { e.backtrace.join("\n") }
            msg = "Oops, something went wrong processing that command (#{e.class}, #{e.message})"
          end

          @bot ||= @siblings && @siblings.detect {|sib| sib.respond_to?(:announce) }

          if @bot && (room || nick)
            if room
              Flapjack.logger.info "sending to room #{room}: #{msg}"
              @bot.announce(room, msg)
            else
              Flapjack.logger.info "sending to user #{nick}: #{msg}"
              @bot.say(nick, msg)
            end
          else
            Flapjack.logger.warn "jabber bot not running, won't send #{msg} to #{room || nick}"
          end

          action.call if action
        end

      end

      class Bot

        attr_accessor :siblings

        def initialize(opts = {})
          @lock = opts[:lock]
          @stop_cond = opts[:stop_condition]
          @config = opts[:config]
          @boot_time = opts[:boot_time]

          @say_buffer = []
          @announce_buffer = []
          @hostname = Socket.gethostname

          @alias = @config['alias'] || 'flapjack'
          @identifiers = ((@config['identifiers'] || []) + [@alias]).uniq

          @state_buffer = []
          @should_quit = false
        end

        def alias
          ret = nil
          @lock.synchronize do
            ret = @alias
          end
          ret
        end

        def identifiers
          ret = nil
          @lock.synchronize do
            ret = @identifiers
          end
          ret
        end

        def start
          Flapjack.logger.debug("I will respond to the following identifiers: #{@identifiers.join(', ')}")

          @lock.synchronize do
            interpreter = self.siblings ? self.siblings.detect {|sib| sib.respond_to?(:interpret)} : nil

            Flapjack.logger.info("starting")
            Flapjack.logger.debug("new jabber pikelet with the following options: #{@config.inspect}")

            # ::Jabber::debug = true

            jabber_id = @config['jabberid'] || 'flapjack'
            jabber_id += '/' + @hostname unless jabber_id.include?('/')
            flapjack_jid = ::Jabber::JID.new(jabber_id)
            client = ::Jabber::Client.new(flapjack_jid)

            client.on_exception do |exc, stream, loc|
              leave_and_rejoin = nil

              @lock.synchronize do

                # called with a nil exception on disconnect for some reason
                if exc
                  Flapjack.logger.error exc.class.name
                  Flapjack.logger.error ":#{loc.to_s}"
                  Flapjack.logger.error exc.message
                  Flapjack.logger.error exc.backtrace.join("\n")
                end

                leave_and_rejoin = @joined && !@should_quit

                if leave_and_rejoin
                  @state_buffer << 'leave'
                  @stop_cond.signal
                end
              end

              if leave_and_rejoin
                sleep 3
                @lock.synchronize do
                  unless @should_quit
                    @state_buffer << 'rejoin'
                    @stop_cond.signal
                  end
                end
              end
            end

            check_xml = Proc.new do |data|
              if data.nil?
                nil
              else
                Flapjack.logger.debug "xml_data: #{data}"
                text = ''
                begin
                  enc_name = Encoding.default_external.name
                  REXML::Document.new("<?xml version=\"1.0\" encoding=\"#{enc_name}\"?>" + data).
                    each_element_with_text do |elem|

                    text += elem.texts.join(" ")
                  end
                  text = data if text.empty? && !data.empty?
                rescue REXML::ParseException
                  # invalid XML, so we'll just clear everything inside angled brackets
                  text = data.gsub(/<[^>]+>/, '').strip
                end
                text
              end
            end

            client.add_message_callback do |m|
              unless (m.type != :chat) || m.body.nil? || m.body.strip.empty?
                Flapjack.logger.debug "received message #{m.inspect}"
                nick = m.from
                time = nil
                m.each_element('x') { |x|
                  if x.kind_of?(::Jabber::Delay::XDelay)
                    time = x.stamp
                  end
                }

                unless interpreter.nil?
                  interpreter.receive_message(nil, nick, time, check_xml.call(m.body))
                end
              end
            end

            muc_clients = @config['rooms'].inject({}) do |memo, room|
              muc_client = ::Jabber::MUC::SimpleMUCClient.new(client)
              muc_client.on_message do |time, nick, text|
                Flapjack.logger.debug("message #{text} -- #{time} -- #{nick}")
                next if nick == jabber_id
                identifier = identifiers.detect {|id| /^(?:@#{id}|#{id}:)\s*(.*)/m === check_xml.call(text) }

                unless identifier.nil?
                  the_command = Regexp.last_match(1)
                  Flapjack.logger.debug("matched identifier: #{identifier}, command: #{the_command.inspect}")
                  if interpreter
                    interpreter.receive_message(room, nick, time, the_command)
                  end
                end
              end

              memo[room] = muc_client
              memo
            end

            attempts_allowed = 3
            attempts_remaining = attempts_allowed
            @joined = false

            loop do

              if @joined
                # block this thread until signalled to quit / leave / rejoin
                @stop_cond.wait_until { @should_quit || !@state_buffer.empty? }
              elsif attempts_remaining > 0
                unless @should_quit || (attempts_remaining == attempts_allowed)
                  # The only thing that should be interrupting this wait is
                  # a pikelet.stop, which would set @should_quit to true;
                  # thus we shouldn't see multiple connection attempts happening
                  # too quickly.
                  @stop_cond.wait(3)
                end
                unless @should_quit # may have changed during previous wait
                  begin
                    attempts_remaining -= 1
                    _join(client, muc_clients)
                    @joined = true
                  rescue Errno::ECONNREFUSED, ::Jabber::JabberError => je
                    report_error("Couldn't join Jabber server #{@hostname}", je)
                  end
                end
              else
                # TODO should we quit Flapjack entirely?
                Flapjack.logger.error "stopping jabber bot, couldn't connect in #{attempts_allowed} attempts"
                @should_quit = true
              end

              break if @should_quit
              handle_state_change(client, muc_clients) unless @state_buffer.empty?
            end

            # main loop has finished, stop() must have been called -- disconnect
            _leave(client, muc_clients) if client.is_connected?
          end
        end

        def announce(room, msg)
          @lock.synchronize do
            @announce_buffer += [{:room => room, :msg => msg}]
            @state_buffer << 'announce'
            @stop_cond.signal
          end
        end

        def say(nick, msg)
          @lock.synchronize do
            @say_buffer += [{:nick => nick, :msg => msg}]
            @state_buffer << 'say'
            @stop_cond.signal
          end
        end

        def handle_state_change(client, muc_clients)
          connected = client.is_connected?
          Flapjack.logger.debug "connected? #{connected}"

          while state = @state_buffer.pop
            Flapjack.logger.debug "state change #{state}"
            case state
            when 'announce'
              _announce(muc_clients) if connected
            when 'say'
              _say(client) if connected
            when 'leave'
              connected ? _leave(client, muc_clients) : _deactivate(muc_clients)
            when 'rejoin'
              _join(client, muc_clients, :rejoin => true) unless connected
            else
              Flapjack.logger.warn "unknown state change #{state}"
            end
          end
        end

        def stop_type
          :signal
        end

        def report_error(error_msg, je)
          Flapjack.logger.error error_msg
          message = je.respond_to?(:message) ? je.message : '-'
          Flapjack.logger.error "#{je.class.name} #{message}"
          # if je.respond_to?(:backtrace) && trace = je.backtrace
          #   Flapjack.logger.error trace.join("\n")
          # end
        end

        def _join(client, muc_clients, opts = {})
          client.connect
          client.auth(@config['password'])
          client.send(::Jabber::Presence.new)
          muc_clients.each_pair do |room, muc_client|
            attempts_allowed = 3
            attempts_remaining = attempts_allowed
            joined = nil
            while !joined && (attempts_remaining > 0)
              @lock.synchronize do
                unless @should_quit || (attempts_remaining == attempts_allowed)
                  # The only thing that should be interrupting this wait is
                  # a pikelet.stop, which would set @should_quit to true;
                  # thus we shouldn't see multiple connection attempts happening
                  # too quickly.
                  @stop_cond.wait(3)
                end
              end

              # may have changed during previous wait
              sq = nil
              @lock.synchronize do
                sq = @should_quit
              end

              unless sq
                attempts_remaining -= 1
                begin
                  muc_client.join(room + '/' + @alias, nil, :history => false)
                  t = Time.now
                  msg = opts[:rejoin] ? "flapjack jabber gateway rejoining at #{t}, hello again!" :
                                        "flapjack jabber gateway started at #{t}, hello! Try typing 'help'."
                  muc_client.say(msg) if @config['chatbot_announce']
                  joined = true
                rescue Errno::ECONNREFUSED, ::Jabber::JabberError => muc_je
                  report_error("Couldn't join MUC room #{room}, #{attempts_remaining} attempts remaining", muc_je)
                  raise if attempts_remaining <= 0
                  joined = false
                end
              end
            end
          end
        end

        def _leave(client, muc_clients)
          if @joined
            muc_clients.values.each {|muc_client| muc_client.exit if muc_client.active? }
            client.close
          end
          @joined = false
        end

        def _deactivate(muc_clients)
          # send method has been overridden in MUCClient class
          # without this MUC clients will still think they are active
          muc_clients.values.each {|muc_client| muc_client.__send__(:deactivate) }
        end

        def _announce(muc_clients)
          @announce_buffer.each do |announce|
            if (muc_client = muc_clients[announce[:room]]) && muc_client.active?
              muc_client.say(announce[:msg])
              announce[:sent] = true
            end
          end
          @announce_buffer.delete_if {|announce| announce[:sent] }
        end

        def _say(client)
          while speak = @say_buffer.pop
            msg = ::Jabber::Message::new(speak[:nick], speak[:msg])
            msg.type = :chat
            client.send( msg )
          end
        end

      end

    end
  end
end
