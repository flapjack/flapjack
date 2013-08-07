#!/usr/bin/env ruby

require 'monitor'
require 'socket'

require 'chronic_duration'
require 'oj'
require 'xmpp4r'
require 'xmpp4r/muc/helper/simplemucclient'

require 'flapjack/data/entity_check'
require 'flapjack/data/message'

require 'flapjack/exceptions'
require 'flapjack/utility'
require 'flapjack/version'

module Flapjack

  module Gateways

    module Jabber

      class Notifier

        attr_accessor :siblings

        include MonitorMixin

        def initialize(options = {})
          @config = options[:config]
          @redis_config = options[:redis_config] || {}

          @logger = options[:logger]

          @notifications_queue = @config['queue'] || 'jabber_notifications'

          mon_initialize

          @redis = Redis.new(@redis_config.merge(:driver => :hiredis))
        end

        def start
          loop do
            synchronize do
              Flapjack::Data::Message.foreach_on_queue(@notifications_queue, :redis => @redis) {|message|
                handle_message(message)
              }
            end

            Flapjack::Data::Message.wait_for_queue(@notifications_queue, :redis => @redis)
          end
        rescue Flapjack::PikeletStop => fps
          @logger.info "stopping jabber notifier"
        end

        def stop(thread)
          synchronize do
            thread.raise Flapjack::PikeletStop.new
          end
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

        include MonitorMixin

        attr_accessor :siblings

        include Flapjack::Utility

        def initialize(opts = {})
          @config = opts[:config]
          @redis_config = opts[:redis_config] || {}
          @boot_time = opts[:boot_time]
          @logger = opts[:logger]

          @redis = Redis.new(@redis_config.merge(:driver => :hiredis))

          @should_quit = false

          mon_initialize

          @message_cond = new_cond
          @messages = []
        end

        def start
          synchronize do
            until @messages.empty? && @should_quit
              while msg = @messages.pop
                @logger.info "interpreter received #{msg.inspect}"
                interpret(msg[:room], msg[:nick], msg[:time], msg[:message])
              end
              @message_cond.wait_while { @messages.empty? && !@should_quit }
            end
          end
        end

        def stop
          synchronize do
            @should_quit = true
            @message_cond.signal
          end
        end

        def receive_message(room, nick, time, msg)
          synchronize do
            @messages += [{:room => room, :nick => nick, :time => time, :message => msg}]
            @message_cond.signal
          end
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

            event_id = @redis.hget('unacknowledged_failures', ackid)

            if event_id.nil?
              error = "not found"
            else
              entity_check = Flapjack::Data::EntityCheck.for_event_id(event_id, :redis => @redis)
              error = "unknown entity" if entity_check.nil?
            end

            if error
              msg = "ERROR - couldn't ACK #{ackid} - #{error}"
            else
              entity_name, check = event_id.split(':', 2)

              if entity_check.in_unscheduled_maintenance?
                # ack = entity_check.current_maintenance(:unscheduled => true)
                # FIXME details from current?
                msg = "Changing ACK for #{check} on #{entity_name} (#{ackid})"
              else
                msg = "ACKing #{check} on #{entity_name} (#{ackid})"
              end
              action = Proc.new {
                Flapjack::Data::Event.create_acknowledgement(
                  @config['processor_queue'] || 'events',
                  entity_name, check,
                  :summary => (comment || ''),
                  :acknowledgement_id => ackid,
                  :duration => duration,
                  :redis => @redis
                )
              }
            end
          when /^help$/
            msg = "commands: \n" +
                  "  ACKID <id> <comment> [duration: <time spec>] \n" +
                  "  find entities matching /pattern/ \n" +
                  "  test notifications for <entity>[:<check>] \n" +
                  "  tell me about <entity>[:<check>] \n" +
                  "  identify \n" +
                  "  help \n"

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

            if entity = Flapjack::Data::Entity.find_by_name(entity_name, :redis => @redis)
              msg = "so you want me to test notifications for entity: #{entity_name}, check: #{check_name} eh? ... well OK!"

              summary = "Testing notifications to all contacts interested in entity: #{entity_name}, check: #{check_name}"
              Flapjack::Data::Event.test_notifications(@config['processor_queue'] || 'events',
                entity_name, check_name, :summary => summary, :redis => @redis)
            else
              msg = "yeah, no I can't see #{entity_name} in my systems"
            end

          when /^tell me about\s+([a-z0-9\-\.]+)(?::(.+))?$+/
            entity_name = $1
            check_name  = $2

            if entity = Flapjack::Data::Entity.find_by_name(entity_name, :redis => @redis)
              check_str = check_name.nil? ? '' : ", check: #{check_name}"
              msg = "so you'd like details on entity: #{entity_name}#{check_str} hmm? ... OK!\n"

              current_time = Time.now

              get_details = proc {|entity_check|
                sched   = entity_check.current_maintenance(:scheduled => true)
                unsched = entity_check.current_maintenance(:unscheduled => true)
                out = ''

                if check_name.nil?
                  check = entity_check.check
                  out += "---\n#{entity_name}:#{check}\n"
                end

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
              }

              check_names = check_name.nil? ? entity.check_list.sort : [check_name]

              if check_names.empty?
                msg += "I couldn't find any checks for entity: #{entity_name}"
              else
                check_names.each do |check|
                  entity_check = Flapjack::Data::EntityCheck.for_entity(entity, check, :redis => @redis)
                  next if entity_check.nil?
                  msg += get_details.call(entity_check)
                end
              end
            else
              msg = "hmmm, I can't see #{entity_name} in my systems"
            end

          when /^(?:find )?entities matching\s+\/(.*)\/.*$/i
            pattern = $1.chomp.strip

            entity_list = Flapjack::Data::Entity.find_all_name_matching(pattern, :redis => @redis)

            if entity_list
              max_showable = 30
              number_found = entity_list.length
              entity_list = entity_list[0..(max_showable - 1)] if number_found > max_showable

              case
              when number_found == 0
                msg = "found no entities matching /#{pattern}/"
              when number_found == 1
                msg = "found #{number_found} entity matching /#{pattern}/ ... \n"
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

        include MonitorMixin

        attr_accessor :siblings

        def initialize(opts = {})
          @config = opts[:config]
          @redis_config = opts[:redis_config] || {}
          @boot_time = opts[:boot_time]

          @redis = Redis.new(@redis_config.merge(:driver => :hiredis))

          @logger = opts[:logger]

          @buffer = []
          @hostname = Socket.gethostname

          mon_initialize

          @should_quit = false
          @shutdown_cond = new_cond
        end

        # TODO reconnect on disconnect
        def start
          synchronize do
            if self.siblings
              @interpreter = self.siblings.detect {|sib| sib.respond_to?(:interpret)}
            end

            @logger.info("starting")
            @logger.debug("new jabber pikelet with the following options: #{@config.inspect}")

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

            @client.add_message_callback do |m|
              text = m.body
              nick = m.from
              time = nil
              m.each_element('x') { |x|
                if x.kind_of?(::Jabber::Delay::XDelay)
                  time = x.stamp
                end
              }

              if @interpreter
                @interpreter.receive_message(nil, nick, time, text)
              end
            end

            @muc_clients.each_pair do |room, muc_client|
              muc_client.on_message do |time, nick, text|
                next if nick == jabber_id

                if text =~ /^#{@config['alias']}:\s+(.*)/
                  command = $1

                  if @interpreter
                    @interpreter.receive_message(room, nick, time, command)
                  end
                end                
              end

              muc_client.join(room + '/' + @config['alias'])
              muc_client.say("flapjack jabber gateway started at #{Time.now}, hello!")
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

        def say(nick, message)
          synchronize do
            m = ::Jabber::Message::new(nick, message)
            @client.send(m)
          end
        end

      end

    end
  end
end
