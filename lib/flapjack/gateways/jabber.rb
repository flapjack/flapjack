#!/usr/bin/env ruby

require 'socket'

require 'eventmachine'
# the redis/synchrony gems need to be required in this particular order, see
# the redis-rb README for details
require 'hiredis'
require 'em-synchrony'
require 'redis/connection/synchrony'
require 'redis'

require 'blather/client/client'
require 'chronic_duration'
require 'oj'

require 'flapjack/data/entity_check'
require 'flapjack/redis_pool'
require 'flapjack/utility'
require 'flapjack/version'

module Flapjack

  module Gateways

    class Jabber < Blather::Client
      include Flapjack::Utility

      log = ::Logger.new(STDOUT)
      log.level = ::Logger::INFO
      Blather.logger = log

      # TODO if we use 'xmpp4r' rather than 'blather', port this to 'rexml'
      class TextHandler < Nokogiri::XML::SAX::Document
        def initialize
          @chunks = []
        end

        attr_reader :chunks

        def cdata_block(string)
          characters(string)
        end

        def characters(string)
          @chunks << string.strip if string.strip != ""
        end
      end

      def initialize(opts = {})
        @config = opts[:config]
        @redis_config = opts[:redis_config]
        @boot_time = opts[:boot_time]

        @redis = Flapjack::RedisPool.new(:config => @redis_config, :size => 2) # first will block

        @logger = opts[:logger]

        @buffer = []
        @hostname = Socket.gethostname
        super()
      end

      def stop
        @should_quit = true
        @redis.rpush(@config['queue'], Oj.dump('notification_type' => 'shutdown'))
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

        register_handler :message, :groupchat?, :body => /^#{@config['alias']}:\s+/ do |stanza|
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

      def interpreter(command_raw)
        msg          = nil
        action       = nil
        entity_check = nil

        th = TextHandler.new
        parser = Nokogiri::HTML::SAX::Parser.new(th)
        parser.parse(command_raw)
        command = th.chunks.join(' ')

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
                entity_name, check,
                :summary => (comment || ''),
                :acknowledgement_id => ackid,
                :duration => duration,
                :redis => @redis
              )
            }
          end

        when /^help$/i
          msg = "commands: \n" +
                "  ACKID <id> <comment> [duration: <time spec>] \n" +
                "  find entities matching /pattern/ \n" +
                "  test notifications for <entity>[:<check>] \n" +
                "  tell me about <entity>[:<check>] \n" +
                "  identify \n" +
                "  help \n"

        when /^identify$/i
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

          if entity = Flapjack::Data::Entity.find_by_name(entity_name, :redis => @redis)
            msg = "so you want me to test notifications for entity: #{entity_name}, check: #{check_name} eh? ... well OK!"

            summary = "Testing notifications to all contacts interested in entity: #{entity_name}, check: #{check_name}"
            Flapjack::Data::Event.test_notifications(entity_name, check_name, :summary => summary, :redis => @redis)
          else
            msg = "yeah, no I can't see #{entity_name} in my systems"
          end

        when /^tell me about\s+([a-z0-9\-\.]+)(?::(.+))?$+/i
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

        when /^(find )?entities matching\s+\/(.*)\/.*$/i
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

        when /^(.*)/
          words = $1
          msg   = "what do you mean, '#{words}'? Type 'help' for a list of acceptable commands."

        end

        {:msg => msg, :action => action}
      end

      def on_groupchat(stanza)
        return if @should_quit
        @logger.debug("groupchat message received: #{stanza.inspect}")

        if stanza.body =~ /^#{@config['alias']}:\s+(.*)/
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
            event         = Oj.load(events[queue][1])
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
              entity, check = event['event_id'].split(':', 2)
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
                "::: #{@config['alias']}: ACKID #{event['event_count']} " : ''

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

