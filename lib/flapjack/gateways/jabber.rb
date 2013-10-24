#!/usr/bin/env ruby

require 'monitor'
require 'socket'

require 'chronic_duration'
require 'oj'
require 'rexml/document'
require 'xmpp4r/query'
require 'xmpp4r/muc'

require 'flapjack'

require 'flapjack/data/check_state'
require 'flapjack/data/check'
require 'flapjack/data/event'
require 'flapjack/data/message'

require 'flapjack/exceptions'
require 'flapjack/utility'
require 'flapjack/version'

module Flapjack

  module Gateways

    module Jabber

      class Notifier

        attr_accessor :siblings

        def initialize(options = {})
          @lock = options[:lock]
          @config = options[:config]

          @logger = options[:logger]

          @notifications_queue = @config['queue'] || 'jabber_notifications'
        end

        def start
          loop do
            @lock.synchronize do
              Flapjack::Data::Message.foreach_on_queue(@notifications_queue) {|message|
                handle_message(message)
              }
            end

            Flapjack::Data::Message.wait_for_queue(@notifications_queue)
          end
        end

        def stop_type
          :exception
        end

        private

          def handle_message(event)
            type  = event['notification_type'] || 'unknown'
            @logger.info('jabber notification event received')
            @logger.info(event.inspect)

            @bot ||= @siblings && @siblings.detect {|sib| sib.respond_to?(:announce) }

            if @bot.nil?
              @logger.warn("jabber bot not running, won't announce")
              return
            end

            entity, check = event['event_id'].split(':')
            state         = event['state']
            summary       = event['summary']
            duration      = event['duration'] ? time_period_in_words(event['duration']) : '4 hours'
            address       = event['address']

            @logger.debug("processing jabber notification address: #{address}, event: #{entity}:#{check}, state: #{state}, summary: #{summary}")

            ack_str =
              event['event_count'] &&
              !state.eql?('ok') &&
              !'acknowledgement'.eql?(type) &&
              !'test'.eql?(type) ?
              "::: flapjack: ACKID #{event['event_count']} " : ''

            type = 'unknown' unless type

            maint_str = case type
            when 'acknowledgement'
              "has been acknowledged, unscheduled maintenance created for #{duration}"
            when 'test'
              ''
            else
              "is #{state.upcase}"
            end

            # FIXME - should probably put all the message composition stuff in the Message class so
            # the logic isn't duplicated in each notification channel.
            # TODO - templatise the messages so they can be customised without changing core code
            headline = "test".eql?(type.downcase) ? "TEST NOTIFICATION" : type.upcase

            msg = "#{headline} #{ack_str}::: \"#{check}\" on #{entity} #{maint_str} ::: #{summary}"

            # FIXME: should also check if presence has been established in any group chat rooms that are
            # configured before starting to process events, otherwise the first few may get lost (send
            # before joining the group chat rooms)
            @bot.announce(address, msg)
          end

      end

      class Interpreter

        attr_accessor :siblings

        include Flapjack::Utility

        def initialize(opts = {})
          @lock = opts[:lock]
          @stop_cond = opts[:stop_condition]
          @config = opts[:config]

          @boot_time = opts[:boot_time]
          @logger = opts[:logger]

          @should_quit = false

          @messages = []
        end

        def start
          @lock.synchronize do
            until @messages.empty? && @should_quit
              while msg = @messages.pop
                @logger.info "interpreter received #{msg.inspect}"
                interpret(msg[:room], msg[:nick], msg[:time], msg[:message])
              end
              @stop_cond.wait_while { @messages.empty? && !@should_quit }
            end
          end
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

        def get_check_details(entity_check)
          sched   = entity_check.current_scheduled_maintenance
          unsched = entity_check.current_unscheduled_maintenance
          out = ''

          if sched.nil? && unsched.nil?
            out += "Not in scheduled or unscheduled maintenance.\n"
          else
            if sched.nil?
              out += "Not in scheduled maintenance.\n"
            else
              start  = Time.at(sched[:start_time])
              finish = Time.at(sched[:start_time] + sched[:duration])
              remain = time_period_in_words( (finish - current_time).ceil )
              # TODO a simpler time format?
              out += "In scheduled maintenance: #{start} -> #{finish} (#{remain} remaining)\n"
            end

            if unsched.nil?
              out += "Not in unscheduled maintenance.\n"
            else
              start  = Time.at(unsched[:start_time])
              finish = Time.at(unsched[:start_time] + unsched[:duration])
              remain = time_period_in_words( (finish - current_time).ceil )
              # TODO a simpler time format?
              out += "In unscheduled maintenance: #{start} -> #{finish} (#{remain} remaining)\n"
            end
          end

          out
        end

        def interpret(room, nick, time, command)
          msg = nil
          action = nil
          entity_check = nil

          case command
          when /^ACKID\s+(\d+)(?:\s*(.*?)(?:\s*duration:.*?(\w+.*))?)$/i
            ackid        = $1
            comment      = $2
            duration_str = $3

            error = nil
            dur   = nil

            if comment.nil? || (comment.length == 0)
              error = "please provide a comment, eg \"#{@config['alias']}: ACKID #{$1} AL looking\""
            elsif duration_str
              # a fairly liberal match above, we'll let chronic_duration do the heavy lifting
              dur = ChronicDuration.parse(duration_str)
            end

            four_hours = 4 * 60 * 60
            duration = (dur.nil? || (dur <= 0)) ? four_hours : dur

            check_state = Flapjack::Data::CheckState.intersect(:count => ackid).all.first

            if check_state.nil?
              error = "not found"
            else
              entity_check = check_state.entity_check
              error = "unknown entity" if entity_check.nil?
            end

            if error
              msg = "ERROR - couldn't ACK #{ackid} - #{error}"
            else

              entity_name = entity_check.entity_name
              check_name = entity_check.name

              details = "#{check_name} on #{entity_name} (#{ackid})"
              if entity_check.in_unscheduled_maintenance?
                msg = "Changing ACK for #{details}"
              else
                msg = "ACKing #{details}"
              end

              action = Proc.new {
                Flapjack::Data::Event.create_acknowledgement(
                  @config['processor_queue'] || 'events',
                  entity_name, check_name,
                  :summary => (comment || ''),
                  :acknowledgement_id => ackid,
                  :duration => duration,
                )
              }
            end
          when /^help$/
            msg = "commands: \n" +
                  "  ACKID <id> <comment> [duration: <time spec>]\n" +
                  "  find entities matching /pattern/\n" +
                  "  find checks[ matching /pattern/] on (<entity>|entities matching /pattern/)\n" +
                  "  test notifications for <entity>[:<check>]\n" +
                  "  tell me about <entity>[:<check>]\n" +
                  "  identify\n" +
                  "  help\n"
          when /^identify$/
            t    = Process.times
            fqdn = `/bin/hostname -f`.chomp
            pid  = Process.pid
            msg  = "Flapjack #{Flapjack::VERSION} process #{pid} on #{fqdn} \n" +
                   "Boot time: #{@boot_time}\n" +
                   "User CPU Time: #{t.utime}\n" +
                   "System CPU Time: #{t.stime}\n" +
                   `uname -a`.chomp + "\n"

          when /^test notifications for\s+([a-z0-9\-\.]+)(?::(.+))?$/i
            entity_name = $1
            check_name  = $2 || 'test'

            msg = "so you want me to test notifications for entity: #{entity_name}, check: #{check_name} eh? ... well OK!"

            if entity = Flapjack::Data::Entity.intersect(:name => entity_name).all.first
              msg = "so you want me to test notifications for entity: #{entity_name}, check: #{check_name} eh? ... well OK!"

              summary = "Testing notifications to all contacts interested in entity: #{entity_name}, check: #{check_name}"
              Flapjack::Data::Event.test_notifications(@config['processor_queue'] || 'events',
                entity_name, check_name, :summary => summary)
            else
              msg = "yeah, no I can't see #{entity_name} in my systems"
            end

          when /^tell me about\s+([a-z0-9\-\.]+)(?::(.+))?$+/
            entity_name = $1
            check_name  = $2

            if entity = Flapjack::Data::Entity.intersect(:name => entity_name).all.first
              check_str = check_name.nil? ? '' : ", check: #{check_name}"
              msg = "so you'd like details on entity: #{entity_name}#{check_str} hmm? ... OK!\n"

              current_time = Time.now

              checks = if check_name.nil?
                entity.checks.all.sort_by(&:name)
              else
                [Flapjack::Data::Check.
                  intersect(:entity_name => entity_name, :name => check_name).
                    all.first].compact
              end

              if checks.empty?
                msg += "I couldn't find any checks for entity: #{entity_name}"
              else
                checks.each do |check|
                  msg += "---\n#{entity_name}:#{check.name}\n" if check_name.nil?
                  msg += get_check_details(check)
                end
              end
            else
              msg = "hmmm, I can't see #{entity_name} in my systems"
            end

          when /^(?:find )?checks(?:\s+matching\s+\/(.+)\/)?\s+on\s+(?:entities matching\s+\/(.+)\/|([a-z0-9\-\.]+))/i
            check_pattern = $1 ? $1.chomp.strip : nil
            entity_pattern = $2 ? $2.chomp.strip : nil
            entity_name = $3

            entity_names = if entity_name
              [entity_name]
            elsif entity_pattern
              Flapjack::Data::Entity.find_all_name_matching(entity_pattern)
            else
              []
            end

            msg = ""

            # hash with entity => check_list, filtered by pattern if required
            entities = entity_names.map {|name|
              Flapjack::Data::Entity.find_by_name(name)
            }.compact.inject({}) {|memo, entity|
              memo[entity] = entity.check_list.select {|check_name|
                !check_pattern || (check_name =~ /#{check_pattern}/i)
              }
              memo
            }

            report_entities = proc {|ents|
              ents.inject('') do |memo, (entity, check_list)|
                if check_list.empty?
                  memo += "Entity: #{entity.name} has no checks\n"
                else
                  memo += "Entity: #{entity.name}\nChecks: #{check_list.join(', ')}\n"
                end
                memo += "----\n"
                memo
              end
            }

            case
            when entity_pattern
              if entities.empty?
                msg = "found no entities matching /#{entity_pattern}/"
              else
                msg = "found #{entities.size} entities matching /#{entity_pattern}/ ... \n" +
                      report_entities.call(entities)
              end
            when entity_name
              if entities.empty?
                msg = "found no entity for '#{entity_name}'"
              else
                msg = report_entities.call(entities)
              end
            end

          when /^(?:find )?entities matching\s+\/(.*)\/.*$/i
            pattern = $1.chomp.strip

            entity_list = Flapjack::Data::Entity.find_all_name_matching(pattern)

            if entity_list
              max_showable = 30
              number_found = entity_list.length
              entity_list = entity_list[0..(max_showable - 1)] if number_found > max_showable

              case
              when number_found == 0
                msg = "found no entities matching /#{pattern}/"
              when number_found == 1
                msg = "found 1 entity matching /#{pattern}/ ... \n"
              when number_found > max_showable
                msg = "showing first #{max_showable} of #{number_found} entities found matching /#{pattern}/\n"
              else
                msg = "found #{number_found} entities matching /#{pattern}/ ... \n"
              end
              msg += entity_list.join(', ') unless entity_list.empty?

            else
              msg = "that doesn't seem to be a valid pattern - /#{pattern}/"
            end

          when /^(.*)/
            words = $1
            msg   = "what do you mean, '#{words}'? Type 'help' for a list of acceptable commands."

          end

          @bot ||= @siblings && @siblings.detect {|sib| sib.respond_to?(:announce) }

          if @bot && (room || nick)
            if room
              @logger.info "sending to room #{room}: #{msg}"
              @bot.announce(room, msg)
            else
              @logger.info "sending to user #{nick}: #{msg}"
              @bot.say(nick, msg)
            end
          else
            @logger.warn "jabber bot not running, won't send #{msg} to #{room || nick}"
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

          @logger = opts[:logger]

          @say_buffer = []
          @announce_buffer = []
          @hostname = Socket.gethostname

          @state_buffer = []
        end

        def start
          @lock.synchronize do
            interpreter = self.siblings ? self.siblings.detect {|sib| sib.respond_to?(:interpret)} : nil

            @logger.info("starting")
            @logger.debug("new jabber pikelet with the following options: #{@config.inspect}")

            # ::Jabber::debug = true

            jabber_id = @config['jabberid'] || 'flapjack'

            flapjack_jid = ::Jabber::JID.new(jabber_id + '/' + @hostname)
            client = ::Jabber::Client.new(flapjack_jid)

            client.on_exception do |exc, stream, loc|
              leave_and_rejoin = nil

              @lock.synchronize do

                # called with a nil exception on disconnect for some reason
                if exc
                  @logger.error exc.class.name
                  @logger.error ":#{loc.to_s}"
                  @logger.error exc.message
                  @logger.error exc.backtrace.join("\n")
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
              return if data.nil?
              @logger.debug "xml_data: #{data}"
              text = ''
              begin
                enc_name = Encoding.default_external.name
                REXML::Document.new("<?xml version=\"1.0\" encoding=\"#{enc_name}\"?>" + data).
                  each_element_with_text do |elem|

                  text += elem.texts.join(" ")
                end
                text = data if text.empty? && !data.empty?
              rescue REXML::ParseException => exc
                # invalid XML, so we'll just clear everything inside angled brackets
                text = data.gsub(/<[^>]+>/, '').strip
              end
              text
            end

            client.add_message_callback do |m|
              text = m.body
              nick = m.from
              time = nil
              m.each_element('x') { |x|
                if x.kind_of?(::Jabber::Delay::XDelay)
                  time = x.stamp
                end
              }

              if interpreter
                interpreter.receive_message(nil, nick, time, check_xml.call(text))
              end
            end

            muc_clients = @config['rooms'].inject({}) do |memo, room|
              muc_client = ::Jabber::MUC::SimpleMUCClient.new(client)
              muc_client.on_message do |time, nick, text|
                next if nick == jabber_id

                if check_xml.call(text) =~ /^#{@config['alias']}:\s+(.*)/
                  command = $1

                  if interpreter
                    interpreter.receive_message(room, nick, time, command)
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
                @logger.error "stopping jabber bot, couldn't connect in #{attempts_allowed} attempts"
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
          @logger.info "connected? #{connected}"

          while state = @state_buffer.pop
            @logger.info "state change #{state}"
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
              @logger.warn "unknown state change #{state}"
            end
          end
        end

        def stop_type
          :signal
        end

        def report_error(error_msg, je)
          @logger.error error_msg
          message = je.respond_to?(:message) ? je.message : '-'
          @logger.error "#{je.class.name} #{message}"
          # if je.respond_to?(:backtrace) && trace = je.backtrace
          #   @logger.error trace.join("\n")
          # end
        end

        def _join(client, muc_clients, opts = {})
          client.connect
          client.auth(@config['password'])
          client.send(::Jabber::Presence.new.set_type(:available))
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
                  muc_client.join(room + '/' + @config['alias'])
                  t = Time.now
                  msg = opts[:rejoin] ? "flapjack jabber gateway rejoining at #{t}, hello again!" :
                                        "flapjack jabber gateway started at #{t}, hello!"
                  muc_client.say(msg)
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
            client.send( ::Jabber::Message::new(speak[:nick], speak[:msg]) )
          end
        end

      end

    end
  end
end
