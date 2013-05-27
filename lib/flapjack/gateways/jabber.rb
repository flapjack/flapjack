#!/usr/bin/env ruby

require 'socket'
require 'monitor'

require 'chronic_duration'
require 'blather/client/dsl'
require 'yajl/json_gem'

require 'flapjack/data/entity_check'
require 'flapjack/redis_pool'
require 'flapjack/utility'
require 'flapjack/version'

module Flapjack

  module Gateways

    module Jabber

      class Notifier

        def self.pikelet_settings
          {:em_synchrony => true,
           :em_stop      => true}
        end

        def initialize(options = {})
          @bot = options[:jabber_bot]

          @config = options[:config]
          @redis_config = options[:redis_config]

          @logger = options[:logger]

          @redis = Flapjack::RedisPool.new(:config => @redis_config, :size => 2)
        end

        def stop
          # TODO synchronize access to @should_quit ??
          @should_quit = true
          @redis.rpush(@config['queue'], JSON.generate('notification_type' => 'shutdown'))
        end

        def start
          # simplified to use a single queue only as it makes the shutdown logic easier
          queue = @config['queue']
          events = {}

          # FIXME: should also check if presence has been established in any group chat rooms that are
          # configured before starting to process events, otherwise the first few may get lost (send
          # before joining the group chat rooms)

          until @should_quit

            @logger.debug("jabber is connected so commencing blpop on #{queue}")
            evt = @redis.blpop(queue, 0)
            events[queue] = evt
            event         = Yajl::Parser.parse(events[queue][1])
            type          = event['notification_type'] || 'unknown'
            @logger.info('jabber notification event received')
            @logger.info(event.inspect)
            unless 'shutdown'.eql?(type)
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

              # FIXME - should probably put all the message composition stuff in one place so
              # the logic isn't duplicated in each notification channel.
              # TODO - templatise the messages so they can be customised without changing core code
              headline = "test".eql?(type.downcase) ? "TEST NOTIFICATION" : type.upcase

              msg = "#{headline} #{ack_str}::: \"#{check}\" on #{entity} #{maint_str} ::: #{summary}"

              @bot.announce(msg, address) if @bot
            end

          end

        end

      end

      class BotClient
        include Blather::DSL
      end

      class Bot

        include Flapjack::Utility

        def self.pikelet_settings
          {:em_synchrony => false,
           :em_stop      => false}
        end

        def initialize(opts = {})
          @config = opts[:config]
          @redis_config = opts[:redis_config]

          @redis = Redis.new((@redis_config || {}).merge(:driver => :hiredis))

          @logger = opts[:logger]

          @monitor = Monitor.new

          @buffer = []
          @hostname = Socket.gethostname
        end

        def start
          @logger.info("starting")
          @logger.debug("new jabber pikelet with the following options: #{@config.inspect}")

          @bot_thread = Thread.current

          @flapjack_jid = ::Blather::JID.new((@config['jabberid'] || 'flapjack') + '/' + @hostname)

          @client = Flapjack::Gateways::Jabber::BotClient.new
          @client.setup(@flapjack_jid, @config['password'], @config['server'],
                        @config['port'].to_i)

          @logger.debug("Building jabber connection with jabberid: " +
            @flapjack_jid.to_s + ", port: " + @config['port'].to_s +
            ", server: " + @config['server'].to_s + ", password: " +
            @config['password'].to_s)

          # # FIXME possible to block using filter?
          # clear_handlers :error

          # register_handler :error do |err|
          #   @logger.warn(err.inspect)
          #   # Kernel.throw :halt
          # end

          @client.when_ready do |stanza|
            on_ready(stanza)
          end

          @client.message :groupchat?, :body => /^#{@config['alias']}:\s+/ do |stanza|
            on_groupchat(stanza)
          end

          @client.message :chat? do |stanza|
            on_chat(stanza)
          end

          @client.disconnected do |stanza|
            on_disconnect(stanza)
          end

          connect_with_retry
        end

        def stop
          synced do
            @should_quit = true
            @client.shutdown
          end

          # without this eventmachine in the bot thread seems to wait for
          # an event of some sort (network activity, or a timer firing)
          # before it realises that it has finished.
          # (should maybe use @bot_thread.wakeup instead)
          @bot_thread.run
        end

        def announce(msg, address)
          say(::Blather::JID.new(address), msg,
            (@config['rooms'] || []).include?(address) ? :groupchat : :chat)
        end

        private

        def connect_with_retry
          attempt = 0
          delay = 2
          begin
            attempt += 1
            delay = 10 if attempt > 10
            delay = 60 if attempt > 60
            Kernel.sleep(delay || 3) if attempt > 1
            @logger.debug("attempting connection to the jabber server")
            @client.run
          rescue StandardError => detail
            @logger.error("unable to connect to the jabber server (attempt #{attempt}), retrying in #{delay} seconds...")
            @logger.error("detail: #{detail.message}")
            @logger.debug(detail.backtrace.join("\n"))
            retry unless @should_quit
          end
        end

        def synced(&block)
          ret = nil
          @monitor.synchronize { ret = block.call }
          ret
        end

        # Join the MUC Chat room after connecting.
        def on_ready(stanza)
          ret = synced { @should_quit }
          @logger.info "on_ready #{ret}"
          return if ret
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
              presence = ::Blather::Stanza::Presence.new
              presence.from = @flapjack_jid
              presence.to = ::Blather::JID.new("#{room}/#{@config['alias']}")
              presence << "<x xmlns='http://jabber.org/protocol/muc'/>"
              @client.write_to_stream presence
              say(room, "flapjack jabber gateway started at #{Time.now}, hello!", :groupchat)
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

        def interpreter(command)
          msg          = nil
          action       = nil
          entity_check = nil
          case
          when command =~ /^ACKID\s+(\d+)(?:\s*(.*?)(?:\s*duration:.*?(\w+.*))?)$/i
            ackid        = $1
            comment      = $2
            duration_str = $3

            error = nil
            dur   = nil

            if comment.nil? || (comment.length == 0)
              error = "please provide a comment, eg \"flapjack: ACKID #{$1} AL looking\""
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

            if entity_check && entity_check.in_unscheduled_maintenance?
              error = "#{event_id} is already acknowledged"
            end

            if error
              msg = "ERROR - couldn't ACK #{ackid} - #{error}"
            else
              msg = "ACKing #{entity_check.check} on #{entity_check.entity_name} (#{ackid})"
              action = Proc.new {
                entity_check.create_acknowledgement('summary' => (comment || ''),
                  'acknowledgement_id' => ackid, 'duration' => duration)
              }
            end

          when command =~ /^help$/
            msg  = "commands: \n"
            msg += "  ACKID <id> <comment> [duration: <time spec>] \n"
            msg += "  find entities matching /pattern/ \n"
            msg += "  test notifications for <entity>[:<check>] \n"
            msg += "  identify \n"
            msg += "  help \n"

          when command =~ /^identify$/
            t = Process.times
            fqdn         = `/bin/hostname -f`.chomp
            pid          = Process.pid
            instance_id  = "#{@fqdn}:#{@pid}"
            bt = @redis.hget("executive_instance:#{instance_id}", 'boot_time').to_i
            boot_time = Time.at(bt)
            msg  = "Flapjack #{Flapjack::VERSION} process #{pid} on #{fqdn} \n"
            msg += "Boot time: #{boot_time}\n"
            msg += "User CPU Time: #{t.utime}\n"
            msg += "System CPU Time: #{t.stime}\n"
            msg += `uname -a`.chomp + "\n"

          when command =~ /^test notifications for\s+([a-z0-9\-\.]+)(:(.+))?$/i
            entity_name = $1
            check_name  = $3 ? $3 : 'test'

            msg = "so you want me to test notifications for entity: #{entity_name}, check: #{check_name} eh? ... well OK!"

            entity = Flapjack::Data::Entity.find_by_name(entity_name, :redis => @redis)
            if entity
              summary = "Testing notifications to all contacts interested in entity: #{entity.name}, check: #{check_name}"
              entity_check = Flapjack::Data::EntityCheck.for_entity(entity, check_name, :redis => @redis)
              entity_check.test_notifications('summary' => summary)
            else
              msg = "yeah, no i can't see #{entity_name} in my systems"
            end

          when command =~ /^(find )?entities matching\s+\/(.*)\/.*$/i
            pattern = $2.chomp.strip

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

          when command =~ /^(.*)/
            words = $1
            msg   = "what do you mean, '#{words}'? Type 'help' for a list of acceptable commands."

          end

          {:msg => msg, :action => action}
        end

        def on_groupchat(stanza)
          return if synced { @should_quit }
          @logger.debug("groupchat message received: #{stanza.inspect}")

          if stanza.body =~ /^#{@config['alias']}:\s+(.*)/
            command = $1
          end

          results = interpreter(command)
          msg     = results[:msg]
          action  = results[:action]

          if msg || action
            @logger.info("sending to group chat: #{msg}")
            say(stanza.from.stripped, msg, :groupchat)
            action.call if action
          end
        end

        def on_chat(stanza)
          return if synced { @should_quit }
          @logger.debug("chat message received: #{stanza.inspect}")

          if stanza.body =~ /^flapjack:\s+(.*)/
            command = $1
          else
            command = stanza.body
          end

          results = interpreter(command)
          msg     = results[:msg]
          action  = results[:action]

          if msg || action
            @logger.info("Sending to #{stanza.from.stripped}: #{msg}")
            say(stanza.from.stripped, msg, :chat)
            action.call if action
          end
        end

        # may return true to prevent the reactor loop from stopping
        def on_disconnect(stanza)
          @logger.warn("disconnect handler called")
          @keepalive_timer.cancel unless @keepalive_timer.nil?
          @keepalive_timer = nil
          return false if sq = synced { @connected = false; @should_quit }
          @logger.warn("jabbers disconnected! reconnecting after a short delay...")
          Kernel.sleep(5)
          connect_with_retry
          true
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

