#!/usr/bin/env ruby

require 'socket'

require 'eventmachine'
# the redis/synchrony gems need to be required in this particular order, see
# the redis-rb README for details
require 'hiredis'
require 'em-synchrony'
require 'redis/connection/synchrony'
require 'redis'

require 'chronic_duration'

require 'blather/client/client'
require 'em-synchrony/fiber_iterator'
require 'yajl/json_gem'

require 'flapjack/data/entity_check'
require 'flapjack/redis_pool'
require 'flapjack/utility'
require 'flapjack/version'

module Flapjack

  module Gateways

    class Jabber < Blather::Client
      include Flapjack::Utility

      log = Logger.new(STDOUT)
      # log.level = Logger::DEBUG
      log.level = Logger::INFO
      Blather.logger = log

      def initialize(opts = {})
        @config = opts[:config]
        @redis_config = opts[:redis_config]
        @redis = Flapjack::RedisPool.new(:config => @redis_config, :size => 2) # first will block

        @logger = opts[:logger]

        @buffer = []
        @hostname = Socket.gethostname
        super()
      end

      def stop
        @should_quit = true
        @redis.rpush(@config['queue'], JSON.generate('notification_type' => 'shutdown'))
      end

      def setup
        @flapjack_jid = Blather::JID.new((@config['jabberid'] || 'flapjack') + '/' + @hostname)

        super(@flapjack_jid, @config['password'], @config['server'], @config['port'].to_i)

        @logger.debug("Building jabber connection with jabberid: " +
          @flapjack_jid.to_s + ", port: " + @config['port'].to_s +
          ", server: " + @config['server'].to_s + ", password: " +
          @config['password'].to_s)

        register_handler :ready do |stanza|
          EventMachine::Synchrony.next_tick do
            on_ready(stanza)
          end
        end

        register_handler :message, :groupchat?, :body => /^flapjack:\s+/ do |stanza|
          EventMachine::Synchrony.next_tick do
            on_groupchat(stanza)
          end
        end

        register_handler :message, :chat? do |stanza|
          EventMachine::Synchrony.next_tick do
            on_chat(stanza)
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
        return if @should_quit
        @connected_at = Time.now.to_i
        @logger.info("Jabber Connected")
        if @config['rooms'] && @config['rooms'].length > 0
          @config['rooms'].each do |room|
            @logger.info("Joining room #{room}")
            presence = Blather::Stanza::Presence.new
            presence.from = @flapjack_jid
            presence.to = Blather::JID.new("#{room}/#{@config['alias']}")
            presence << "<x xmlns='http://jabber.org/protocol/muc'/>"
            EventMachine::Synchrony.next_tick do
              write presence
              say(room, "flapjack jabber gateway started at #{Time.now}, hello!", :groupchat)
            end
          end
        end
        return if @buffer.empty?
        while stanza = @buffer.shift
          @logger.debug("Sending a buffered jabber message to: #{stanza.to}, using: #{stanza.type}, message: #{stanza.body}")
          EventMachine::Synchrony.next_tick do
            write(stanza)
          end
        end
      end

      def interpreter(command)
        msg          = nil
        action       = nil
        entity_check = nil
        case
        when command =~ /^ACKID\s+(\d+)(?:\s*(.*?)(?:\s*duration:.*?(\w+.*))?)$/i;
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
          boot_time = Time.at(@redis.get('boot_time').to_i)
          msg  = "Flapjack #{Flapjack::VERSION} process #{Process.pid} on #{`hostname -f`.chomp} \n"
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
            puts entity_check.inspect
            entity_check.test_notifications('summary' => summary)

          else
            msg = "yeah, no i can't see #{entity_name} in my systems"
          end

        when command =~ /^(find )?entities matching\s+\/(.*)\/.*$/i
          pattern = $2.chomp.strip
          entity_list = Flapjack::Data::Entity.find_all_name_matching(pattern, :redis => @redis)
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

        when command =~ /^(.*)/
          words = $1
          msg   = "what do you mean, '#{words}'? Type 'help' for a list of acceptable commands."

        end

        {:msg => msg, :action => action}
      end

      def on_groupchat(stanza)
        return if @should_quit
        @logger.debug("groupchat message received: #{stanza.inspect}")

        if stanza.body =~ /^flapjack:\s+(.*)/
          command = $1
        end

        results = interpreter(command)
        msg     = results[:msg]
        action  = results[:action]

        if msg || action
          EventMachine::Synchrony.next_tick do
            @logger.info("sending to group chat: #{msg}")
            say(stanza.from.stripped, msg, :groupchat)
            action.call if action
          end
        end
      end

      def on_chat(stanza)
        return if @should_quit
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
          EventMachine::Synchrony.next_tick do
            @logger.info("Sending to #{stanza.from.stripped}: #{msg}")
            say(stanza.from.stripped, msg, :chat)
            action.call if action
          end
        end
      end

      def connect_with_retry
        attempt = 0
        delay = 2
        begin
          attempt += 1
          delay = 10 if attempt > 10
          delay = 60 if attempt > 60
          EventMachine::Synchrony.sleep(delay || 3) if attempt > 1
          @logger.debug("attempting connection to the jabber server")
          connect # Blather::Client.connect
        rescue StandardError => detail
          @logger.error("unable to connect to the jabber server (attempt #{attempt}), retrying in #{delay} seconds ...")
          @logger.error("detail: #{detail.message}")
          @logger.debug(detail.backtrace.join("\n"))
          retry unless @should_quit
        end
      end

      # returning true to prevent the reactor loop from stopping
      def on_disconnect(stanza)
        @logger.warn("disconnect handler called")
        return true if @should_quit
        @logger.warn("jabbers disconnected! reconnecting after a short deley ...")
        EventMachine::Synchrony.sleep(5)
        connect_with_retry
        true
      end

      def say(to, msg, using = :chat, tick = true)
        stanza = Blather::Stanza::Message.new(to, msg, using)
        if connected?
          @logger.debug("Sending a jabber message to: #{to.to_s}, using: #{using.to_s}, message: #{msg}")
          write(stanza)
        else
          @logger.debug("Buffering a jabber message to: #{to.to_s}, using: #{using.to_s}, message: #{msg}")
          @buffer << stanza
        end
      end

      def start
        @logger.info("starting")
        @logger.debug("new jabber pikelet with the following options: #{@config.inspect}")

        keepalive_timer = EM::Synchrony.add_periodic_timer(60) do
          @logger.debug("calling keepalive on the jabber connection")
          if connected?
            EventMachine::Synchrony.next_tick do
              write(' ')
            end
          end
        end

        setup
        connect_with_retry

        # simplified to use a single queue only as it makes the shutdown logic easier
        queue = @config['queue']
        events = {}

        until @should_quit

          # FIXME: should also check if presence has been established in any group chat rooms that are
          # configured before starting to process events, otherwise the first few may get lost (send
          # before joining the group chat rooms)
          if connected?
            @logger.debug("jabber is connected so commencing blpop on #{queue}")
            events[queue] = @redis.blpop(queue, 0)
            event         = Yajl::Parser.parse(events[queue][1])
            type          = event['notification_type'] || 'unknown'
            @logger.debug('jabber notification event received')
            @logger.debug(event.inspect)
            if 'shutdown'.eql?(type)
              if @should_quit
                EventMachine::Synchrony.next_tick do
                  # get delays without the next_tick
                  close # Blather::Client.close
                end
              end
            else
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

              chat_type = :chat
              chat_type = :groupchat if @config['rooms'] && @config['rooms'].include?(address)
              EventMachine::Synchrony.next_tick do
                say(Blather::JID.new(address), msg, chat_type)
              end
            end
          else
            @logger.debug("not connected, sleep 1 before retry")
            EM::Synchrony.sleep(1)
          end
        end

        keepalive_timer.cancel
      end

    end

  end
end

