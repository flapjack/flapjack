#!/usr/bin/env ruby

require 'em-hiredis'

require 'socket'

require 'blather/client/client'
require 'chronic_duration'

require 'flapjack/data/entity_check'
require 'flapjack/redis_pool'
require 'flapjack/utility'
require 'flapjack/version'
require 'flapjack/data/alert'

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
        @redis_config = opts[:redis_config] || {}
        @boot_time = opts[:boot_time]

        @logger = opts[:logger]

        @redis = Flapjack::RedisPool.new(:config => @redis_config, :size => 2, :logger => @logger)

        @logger.debug("Jabber Initializing")

        @buffer = []
        @hostname = Socket.gethostname

        # FIXME: i suspect the following should be in #setup so a config reload updates @identifiers
        # I moved it here so the rspec passes :-/
        @alias = @config['alias'] || 'flapjack'
        @identifiers = ((@config['identifiers'] || []) + [@alias]).uniq
        @logger.debug("I will respond to the following identifiers: #{@identifiers.join(', ')}")

        super()
      end

      def stop
        @should_quit = true
        redis_uri = @redis_config[:path] ||
          "redis://#{@redis_config[:host] || '127.0.0.1'}:#{@redis_config[:port] || '6379'}/#{@redis_config[:db] || '0'}"
        shutdown_redis = EM::Hiredis.connect(redis_uri)
        shutdown_redis.rpush(@config['queue'], Flapjack.dump_json('notification_type' => 'shutdown'))
      end

      def setup
        jid = @config['jabberid'] || 'flapjack'
        jid += '/' + @hostname unless jid.include?('/')
        @flapjack_jid = Blather::JID.new(jid)

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

        body_matchers = @identifiers.inject([]) do |memo, identifier|
          @logger.debug("identifier: #{identifier}, memo: #{memo}")
          memo << {:body => /^#{identifier}[:\s]/}
          memo
        end
        @logger.debug("body_matchers: #{body_matchers}")
        register_handler :message, :groupchat?, body_matchers do |stanza|
          EventMachine::Synchrony.next_tick do
            on_groupchat(stanza)
          end
        end

        register_handler :message, :chat?, :body do |stanza|
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
            presence.to = Blather::JID.new("#{room}/#{@alias}")
            presence << "<x xmlns='http://jabber.org/protocol/muc'><history maxstanzas='0'></x>"
            EventMachine::Synchrony.next_tick do
              write presence
              say(room, "flapjack jabber gateway started at #{Time.now}, hello! Try typing 'help'.", :groupchat) if @config['chatbot_announce']
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

      def get_check_details(entity_check, current_time)
        sched   = entity_check.current_maintenance(:scheduled => true)
        unsched = entity_check.current_maintenance(:unscheduled => true)
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

      def interpreter(command_raw, from)
        msg          = nil
        action       = nil
        entity_check = nil

        th = TextHandler.new
        parser = Nokogiri::HTML::SAX::Parser.new(th)
        parser.parse(command_raw)
        command = th.chunks.join(' ')

        case command
        when /^ACKID\s+([0-9A-F]+)(?:\s*(.*?)(?:\s*duration:.*?(\w+.*))?)$/im
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

          event_id = @redis.hget('checks_by_hash', ackid)

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
                "  ACKID <id> <comment> [duration: <time spec>]\n" +
                "  ack entities /pattern/ <comment> [duration: <time spec>]\n" +
                "  status entities /pattern/\n" +
                "  ack checks /check_pattern/ on /entity_pattern/ <comment> [duration: <time spec>]\n" +
                "  status checks /check_pattern/ on /entity_pattern/\n" +
                "  find entities matching /pattern/\n" +
                "  find checks[ matching /pattern/] on (<entity>|entities matching /pattern/)\n" +
                "  test notifications for <entity>[:<check>]\n" +
                "  tell me about <entity>[:<check>]\n" +
                "  identify\n" +
                "  help\n"

        when /^identify$/i
          t    = Process.times
          fqdn = `/bin/hostname -f`.chomp
          pid  = Process.pid
          msg  = "Flapjack #{Flapjack::VERSION} process #{pid} on #{fqdn}\n" +
                 "Identifiers: #{@identifiers.join(', ')}\n" +
                 "Boot time: #{@boot_time}\n" +
                 "User CPU Time: #{t.utime}\n" +
                 "System CPU Time: #{t.stime}\n" +
                 `uname -a`.chomp + "\n"

        when /^test notifications for\s+([a-z0-9\-\.]+)(?::(.+))?$/im
          entity_name = $1
          check_name  = $2 || 'test'

          if entity = Flapjack::Data::Entity.find_by_name(entity_name, :redis => @redis)
            msg = "so you want me to test notifications for entity: #{entity_name}, check: #{check_name} eh? ... well OK!"

            summary = "Testing notifications to all contacts interested in entity: #{entity_name}, check: #{check_name}"
            Flapjack::Data::Event.test_notifications(entity_name, check_name, :summary => summary, :redis => @redis)
          else
            msg = "yeah, no I can't see #{entity_name} in my systems"
          end

        when /^tell me about\s+([a-z0-9\-\.]+)(?::(.+))?$+/im
          entity_name = $1
          check_name  = $2

          if entity = Flapjack::Data::Entity.find_by_name(entity_name, :redis => @redis)
            check_str = check_name.nil? ? '' : ", check: #{check_name}"
            msg = "so you'd like details on entity: #{entity_name}#{check_str} hmm? ... OK!\n"

            current_time = Time.now

            check_names = check_name.nil? ? entity.check_list.sort : [check_name]

            if check_names.empty?
              msg += "I couldn't find any checks for entity: #{entity_name}"
            else
              check_names.each do |check|
                entity_check = Flapjack::Data::EntityCheck.for_entity(entity, check, :redis => @redis)
                next if entity_check.nil?
                msg += "---\n#{entity_name}:#{check}\n" if check_name.nil?
                msg += get_check_details(entity_check, current_time)
              end
            end
          else
            msg = "hmmm, I can't see #{entity_name} in my systems"
          end

        when /^(?:find )?checks(?:\s+matching\s+\/(.+)\/)?\s+on\s+(?:entities matching\s+\/(.+)\/|([a-z0-9\-\.]+))/im
          check_pattern  = $1 ? $1.strip : nil
          entity_pattern = $2 ? $2.strip : nil
          entity_name    = $3

          entity_names = if entity_name
            [entity_name]
          elsif entity_pattern
            Flapjack::Data::Entity.find_all_name_matching(entity_pattern, :redis => @redis)
          else
            []
          end

          msg = ""

          # hash with entity => check_list, filtered by pattern if required
          entities = entity_names.map {|name|
            Flapjack::Data::Entity.find_by_name(name, :redis => @redis)
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

        when /^(?:find )?entities matching\s+\/(.+)\//im
          pattern = $1.strip
          entity_list = Flapjack::Data::Entity.find_all_name_matching(pattern, :redis => @redis)

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

        when /^(?:ack )?entities\s+\/(.+)\/(?:\s*(.*?)(?:\s*duration:.*?(\w+.*))?)$/i
          entity_pattern   = $1.strip
          comment          = $2 ? $2.strip : nil
          duration_str     = $3 ? $3.strip : '1 hour'
          duration         = ChronicDuration.parse(duration_str)
          entity_list      = Flapjack::Data::Entity.find_all_name_matching(entity_pattern, :redis => @redis)

          if comment.nil? || (comment.length == 0)
            comment = "#{from}: Set via chatbot"
          else
            comment = "#{from}: #{comment}"
          end

          if entity_list
            number_found = entity_list.length
            case
            when number_found == 0
              msg = "found no entities matching /#{entity_pattern}/"
            when number_found >= 1
              failing_list = Flapjack::Data::EntityCheck.find_current_names_failing_by_entity(:redis => @redis)
              entities = failing_list.select {|k,v| v.count >= 1 && entity_list.include?(k) }
              if entities.length >= 1
                entities.each_pair do |entity,check_list|
                  check_list.each do |check|
                    Flapjack::Data::Event.create_acknowledgement(
                      entity, check,
                      :summary => comment,
                      :duration => duration,
                      :redis => @redis
                      )
                  end
                end
                msg = entities.inject("Ack list:\n") {|memo,kv|
                  kv[1].each {|e| memo << "#{kv[0]}:#{e}\n" }
                  memo
                }
            else
              msg = "found no matching entities with failing checks"
            end
          else
            msg = "that doesn't seem to be a valid pattern - /#{pattern}/"
          end
        end

        when /^(?:status )?entities\s+\/(.+)\/.*$/im
          entity_pattern  = $1 ? $1.strip : nil
          entity_names    = Flapjack::Data::Entity.find_all_name_matching(entity_pattern, :redis => @redis)

          if entity_names
            number_found = entity_names.length
            case
            when number_found == 0
              msg = "found no entities matching /#{entity_pattern}/"
            when number_found >= 1
              entities = entity_names.map {|name|
                Flapjack::Data::Entity.find_by_name(name, :redis => @redis)
              }.compact.inject({}) {|memo, entity|
                memo[entity.name] = entity.check_list.map {|check_name|
                  ec = Flapjack::Data::EntityCheck.for_entity(entity, check_name, :redis => @redis)
                  "#{check_name}: #{ec.state}"
                }
                memo
              }
              msg = entities.inject("Status list:\n") {|memo,kv|
                kv[1].each {|e| memo << "#{kv[0]}:#{e}\n"}
                memo
              }
            else
              msg = "found no matching entities with failing checks"
            end
          else
            msg = "that doesn't seem to be a valid pattern - /#{pattern}/"
          end

        when /^(?:ack )?checks\s+\/(.+)\/\s+on\s+\/(.+)\/(?:\s*(.*?)(?:\s*duration:.*?(\w+.*))?)$/i
          check_pattern  = $1.strip
          entity_pattern = $2.strip
          comment        = $3 ? $3.strip : nil
          duration_str   = $4 ? $4.strip : '1 hour'
          duration       = ChronicDuration.parse(duration_str)
          entity_list    = Flapjack::Data::Entity.find_all_name_matching(entity_pattern, :redis => @redis)

          if comment.nil? || (comment.length == 0)
            comment = "#{from}: Set via chatbot"
          else
            comment = "#{from}: #{comment}"
          end

          if entity_list
            number_found = entity_list.length
            case
            when number_found == 0
              msg = "found no entities matching /#{entity_pattern}/"
            when number_found >= 1

              failing_list = Flapjack::Data::EntityCheck.find_current_names_failing_by_entity(:redis => @redis)

              my_failing_checks = Hash[failing_list.map do |k,v|
                if entity_list.include?(k)
                  [k, v.keep_if {|e| e =~ /#{check_pattern}/}].compact
                end
              end]
              if my_failing_checks.delete_if {|k,v| v.empty? }.length >= 1
                my_failing_checks.each_pair do |entity,check_list|
                  check_list.each do |check|
                    Flapjack::Data::Event.create_acknowledgement(
                      entity, check,
                      :summary => comment,
                      :duration => duration,
                      :redis => @redis
                      )
                  end
                end
                msg = my_failing_checks.inject("Ack list:\n") {|memo,kv|
                  kv[1].each {|e| memo << "#{kv[0]}:#{e}\n" }
                  memo
                }
            else
              msg = "found no matching failing checks"
            end
          else
            msg = "that doesn't seem to be a valid pattern - /#{pattern}/"
          end
        end

        when /^(?:status )checks\s+\/(.+?)\/(?:\s+on\s+)?(?:\/(.+)?\/)?/i
          check_pattern  = $1 ? $1.strip : nil
          entity_pattern = $2 ? $2.strip : '.*'
          entity_names   = Flapjack::Data::Entity.find_all_name_matching(entity_pattern, :redis => @redis)

          if entity_names
            number_found = entity_names.length
            case
            when number_found == 0
              msg = "found no entities matching /#{entity_pattern}/"
            when number_found >= 1
              entities = entity_names.map {|name|
                Flapjack::Data::Entity.find_by_name(name, :redis => @redis)
              }.compact.inject({}) {|memo, entity|
                memo[entity.name] = entity.check_list.map {|check_name|
                  if check_name =~ /#{check_pattern}/
                    ec = Flapjack::Data::EntityCheck.for_entity(entity, check_name, :redis => @redis)
                    "#{check_name}: #{ec.state}"
                  end
                }.compact
                memo
              }
              if entities.delete_if {|k,v| v.empty? }.length >= 1
                msg = entities.inject("Status list:\n") {|memo,kv|
                  kv[1].each {|e| memo << "#{kv[0]}:#{e}\n" ; memo }
                  memo
                }
              else
                msg = "found no matching checks"
              end
            else
              msg = "found no matching checks"
            end
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

        the_command = nil
        @identifiers.each do |identifier|
          if stanza.body =~ /^#{identifier}:?\s*(.*)/m
            the_command  = $1
            @logger.debug("matched identifier: #{identifier}, command: #{the_command.inspect}")
            break
          end
        end

        from = stanza.from

        begin
          results = interpreter(the_command, from.to_s)
          msg     = results[:msg]
          action  = results[:action]
        rescue => e
          @logger.debug("Exception when interpreting command '#{the_command}' - #{e.class}, #{e.message}")
          msg = "Oops, something went wrong processing that command (#{e.class}, #{e.message})"
        end

        if msg || action
          EventMachine::Synchrony.next_tick do
            @logger.info("sending to group chat: #{msg}")
            say(from.stripped, msg, :groupchat)
            action.call if action
          end
        end
      end

      def on_chat(stanza)
        return if @should_quit
        @logger.debug("chat message received: #{stanza.inspect}")

        if stanza.body =~ /^flapjack:\s+(.*)/m
          command = $1
        else
          command = stanza.body
        end

        from = stanza.from

        begin
          results = interpreter(command, from.resource.to_s)
          msg     = results[:msg]
          action  = results[:action]
        rescue => e
          @logger.error("Exception when interpreting command '#{command}' - #{e.class}, #{e.message}")
          msg = "Oops, something went wrong processing that command (#{e.class}, #{e.message})"
        end

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

        # the periodic timer can't be halted early (without doing EM.stop) so
        # keep the time short and count the iterations ... could just use
        # EM.sleep(1) in a loop, I suppose
        ki = 0
        keepalive_timer = EventMachine::Synchrony.add_periodic_timer(1) do
          ki += 1
          if ki == 60
            ki = 0
            @logger.debug("calling keepalive on the jabber connection")
            if connected?
              EventMachine::Synchrony.next_tick do
                write(' ')
              end
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
          unless connected?
            @logger.debug("not connected, sleep 1 before retry")
            EM::Synchrony.sleep(1)
            next
          end

          @logger.debug("jabber is connected so commencing blpop on #{queue}")
          events[queue] = @redis.blpop(queue, 0)
          event_json = events[queue][1]
          begin
            event = Flapjack.load_json(event_json)

            @logger.debug('jabber notification event received: ' + event.inspect)

            if 'shutdown'.eql?(event['notification_type'])
              @logger.debug("@should_quit: #{@should_quit}")
              if @should_quit
                EventMachine::Synchrony.next_tick do
                  # get delays without the next_tick
                  close # Blather::Client.close
                end
              end
              next
            end

            alert = Flapjack::Data::Alert.new(event, :logger => @logger)

            @logger.debug("processing jabber notification address: #{alert.address}, entity: #{alert.entity}, " +
                          "check: '#{alert.check}', state: #{alert.state}, summary: #{alert.summary}")

            @ack_str = if alert.state.eql?('ok') || ['test', 'acknowledgement'].include?(alert.type)
              nil
            else
              "#{@config['alias']}: ACKID #{alert.event_hash}"
            end

            message_type = alert.rollup ? 'rollup' : 'alert'

            mydir = File.dirname(__FILE__)
            message_template_path = case
            when @config.has_key?('templates') && @config['templates']["#{message_type}.text"]
              @config['templates']["#{message_type}.text"]
            else
              mydir + "/jabber/#{message_type}.text.erb"
            end
            message_template = ERB.new(File.read(message_template_path), nil, '-')

            @alert = alert
            bnd    = binding

            begin
              message = message_template.result(bnd).chomp
            rescue => e
              @logger.error "Error while excuting the ERB for a jabber message, " +
                "ERB being executed: #{message_template_path}"
              raise
            end

            chat_type = :chat
            chat_type = :groupchat if @config['rooms'] && @config['rooms'].include?(alert.address)
            EventMachine::Synchrony.next_tick do
              say(Blather::JID.new(alert.address), message, chat_type)
              alert.record_send_success!
            end

          rescue => e
            # TODO: have non-fatal errors generate messages (eg via flapjack events or straight to
            # rollbar or similar)
            @logger.error "Error generating or dispatching jabber message: #{e.class}: #{e.message}\n" +
              e.backtrace.join("\n")
            @logger.debug "Message that could not be processed: \n" + event_json
          end
        end

        keepalive_timer.cancel
      end

    end

  end
end

