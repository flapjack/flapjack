#!/usr/bin/env ruby

# Migration script, from v1 to v2 data
#
# Assumes no Flapjack instances running on source or destination DB. Also
# assumes an empty event queue and empty notification queues; best to run an
# instance of Flapjack with the processor disabled to drain out notifications
# prior to running this.

# To see the state of the redis databases before and after, e.g. (using nodejs
# 'npm install redis-dump -g')
#
#  be ruby bin/flapjack-migration migrate --source-db=7 --destination-db=8 --force
#  redis-dump -d 7 >~/Desktop/dump7.txt
#  redis-dump -d 8 >~/Desktop/dump8.txt
#

require 'pp'

require 'optparse'
require 'ostruct'
require 'redis'

ENTITY_PATTERN_FRAGMENT = '[a-zA-Z0-9][a-zA-Z0-9\.\-]*[a-zA-Z0-9]'
CHECK_PATTERN_FRAGMENT  = '.+'
ID_PATTERN_FRAGMENT     = '.+'
TAG_PATTERN_FRAGMENT    = '.+'

# silence deprecation warning
require 'i18n'
I18n.config.enforce_available_locales = true

require 'hiredis'
require 'zermelo'

require 'flapjack'
require 'flapjack/data/condition'
require 'flapjack/data/check'
require 'flapjack/data/state'
require 'flapjack/data/contact'
require 'flapjack/data/medium'
require 'flapjack/data/rule'
require 'flapjack/data/route'
require 'flapjack/data/scheduled_maintenance'
require 'flapjack/data/unscheduled_maintenance'
require 'flapjack/data/tag'

module Flapjack
  module CLI
    class Migrate

      def initialize(global_options, options)
        @global_options = global_options
        @options = options

        unless options[:'yes-i-know-its-not-finished']
          exit_now! "Until Flapjack v2 is released, the migrate command requires the '--yes-i-know-its-not-finished' switch"
        end

        config = Flapjack::Configuration.new

        if options[:source].nil? || options[:source].strip.empty?
          config.load(global_options[:config])
          config_env = config.all
        end

        @source_redis_options = config.for_redis
      end

      def to_v2
        source_addr = (@options[:source].nil? || @options[:source].strip.empty?) ?
          @source_redis_options : @options[:source]

        @source_redis = case source_addr
        when Hash
          Redis.new(source_addr.merge(:driver => :hiredis))
        when String
          Redis.new(:url => source_addr, :driver => :hiredis)
        else
          exit_now! "could not understand source Redis config"
        end

        dest_addr = @options[:destination]
        dest_redis = Redis.new(:url => dest_addr, :driver => :hiredis)

        Zermelo.redis = dest_redis

        dest_db_size = Zermelo.redis.dbsize
        if dest_db_size > 0
          if @options[:force]
            Zermelo.redis.flushdb
            puts "Cleared #{@options[:destination]} db"
          else
            exit_now! "Destination db #{@options[:destination]} has " \
              "#{dest_db_size} keys, and the --force option was not provided"
          end
        end

        # key is old contact_id, value = new contact id
        @contact_id_cache = {}

        # key is entity_name:check_name, value is zermelo record
        @check_name_cache = {}

        # key is tag name, value is zermelo record
        @tag_name_cache = {}

        # cache old entity/check <-> contact linkage, use as limiting set in
        # rule construction
        @check_ids_by_contact_id_cache = {}


        migrate_contacts_and_media
        migrate_checks

        migrate_contact_entity_linkages

        migrate_rules

        migrate_states
        migrate_actions

        migrate_scheduled_maintenances
        migrate_unscheduled_maintenances # TODO notification data into entries?

        # NB 'alerting checks' data isn't migrated, as it's not always possible to
        # know which routes (in the new schema) would have caused the alert.
        # TODO output a warning if any of these are set

      rescue Exception => e
        puts e.message
        trace = e.backtrace.join("\n")
        puts trace
        # TODO output data, set exit status
        exit 1
      end

      private

      # no dependencies
      def migrate_contacts_and_media
        contact_keys = @source_redis.keys('contact:*')

        contact_keys.each do |contact_key|

          # TODO fix regex, check current code
          unless contact_key =~ /\Acontact:(#{ID_PATTERN_FRAGMENT})\z/
            raise "Bad regex for '#{contact_key}'"
          end

          contact_id = $1
          contact_data = @source_redis.hgetall(contact_key).merge(:id => contact_id)

          timezone = @source_redis.get("contact_tz:#{contact_id}")

          media_addresses = @source_redis.hgetall("contact_media:#{contact_id}")
          media_intervals = @source_redis.hgetall("contact_media_intervals:#{contact_id}")
          media_rollup_thresholds = @source_redis.hgetall("contact_media_rollup_thresholds:#{contact_id}")

          # skipped pagerduty media (moved to gateway config)
          # TODO output warning if pagerduty media is found

          contact = Flapjack::Data::Contact.new(:name =>
              "#{contact_data['first_name']} #{contact_data['last_name']}",
            :timezone => timezone)
          contact.save
          raise contact.errors.full_messages.join(", ") unless contact.persisted?

          media_addresses.each_pair do |media_type, address|
            medium = Flapjack::Data::Medium.new(:transport => media_type,
              :address => address, :interval => media_intervals[media_type].to_i,
              :rollup_threshold => media_rollup_thresholds[media_type].to_i)
            medium.save
            raise medium.errors.full_messages.join(", ") unless medium.persisted?

            contact.media << medium
          end

          @contact_id_cache[contact_id] = contact.id
        end
      end

      def migrate_checks
        entity_tag_keys = @source_redis.keys('entity_tag:*')

        all_entity_names_by_id = @source_redis.hgetall('all_entity_names_by_id')

        entity_tags_by_entity_name = {}

        entity_tag_keys.each do |entity_tag_key|

          # TODO fix regex, check current code
          unless entity_tag_key =~ /\Aentity_tag:(#{TAG_PATTERN_FRAGMENT})\z/
            raise "Bad regex for '#{entity_tag_key}'"
          end

          entity_tag = $1
          entity_ids = @source_redis.smembers(entity_tag_key)

          entity_ids.each do |entity_id|
            entity_name = entity_names_by_id[entity_id]
            raise "No entity name for id #{entity_id}" if entity_name.nil? || entity_name.empty?

            entity_tags_by_entity_name[entity_name] ||= []
            entity_tags_by_entity_name[entity_name] << entity_tag
          end
        end

        all_checks_keys     = @source_redis.keys('all_checks:*')

        all_checks_keys.each do |all_checks_key|
          unless all_checks_key =~ /\Aall_checks:(#{ENTITY_PATTERN_FRAGMENT})\z/
            raise "Bad regex"
          end

          entity_name = $1

          entity_tags = entity_tags_by_entity_name[entity_name]

          all_check_names     = @source_redis.zrange(all_checks_key, 0, -1)
          current_check_names = @source_redis.zrange("current_checks:#{entity_name}", 0, -1)

          all_check_names.each do |check_name|
            check = find_check(entity_name, check_name, :create => true)
            check.enabled = current_check_names.include?(check_name)
            check.save

            check.tags << find_tag("entity_#{entity_name}", :create => true)

            if !entity_tags.nil? && !entity_tags.empty?
              tags = entity_tags.collect do |entity_tag|
                find_tag("entitytag_#{entity_tag}", :create => true)
              end
              check.tags.add(*tags)
            end
          end
        end
      end


      # depends on contacts & checks
      def migrate_contact_entity_linkages
        contacts_for_keys = @source_redis.keys('contacts_for:*')

        all_entity_names_by_id = @source_redis.hgetall('all_entity_names_by_id')

        contacts_for_keys.each do |contacts_for_key|

          unless contacts_for_key =~ /\Acontacts_for:(#{ID_PATTERN_FRAGMENT})(?::(#{CHECK_PATTERN_FRAGMENT}))?\z/
            raise "Bad regex for '#{contacts_for_key}'"
          end

          entity_id   = $1
          check_name  = $2
          entity_name = all_entity_names_by_id[entity_id]

          contact_ids = @source_redis.smembers(contacts_for_key)
          next if contact_ids.empty?

          contacts = contact_ids.collect {|c_id| find_contact(c_id) }

          contacts.each do |contact|
            @check_ids_by_contact_id_cache[contact.id] ||= []
          end

          tag_for_check = proc do |en, cn, tn|
            check = find_check(en, cn)
            check.tags << find_tag(tn, :create => true)

            contacts.each do |contact|
              @check_ids_by_contact_id_cache[contact.id] << check.id
            end
          end

          if check_name.nil?
            # interested in entity, so apply to all checks for that entity
            tag_name = "entity_#{entity_name}"

            all_checks_for_entity = @source_redis.zrange("all_checks:#{entity_name}", 0, -1)
            all_checks_for_entity.each do |check_name|
              tag_for_check.call(entity_name, check_name, tag_name)
            end
          else
            # interested in check
            tag_for_check.call(entity_name, check_name,
              "check_#{entity_name}:#{check_name}")
          end
        end
      end

      # depends on checks
      def migrate_states
        timestamp_keys = @source_redis.keys('*:*:states')
        timestamp_keys.each do |timestamp_key|
          # TODO fix regex, check current code
          unless timestamp_key =~ /\A(#{ENTITY_PATTERN_FRAGMENT}):(#{CHECK_PATTERN_FRAGMENT}):states\z/
            raise "Bad regex for #{timestamp_key}"
          end

          entity_name = $1
          check_name  = $2

          check = find_check(entity_name, check_name)

          # TODO pagination
          timestamps = @source_redis.lrange(timestamp_key, 0, -1)

          last_notifications = [:warning, :critical, :unknown, :recovery,
                    :acknowledgement].each_with_object({}) do |state, memo|
            ln = @source_redis.get("#{entity_name}:#{check_name}:last_#{state}_notification")
            unless ln.nil? && ln =~ /^\d+$/
              memo[state] = ln
            end
            memo
          end

          most_severe = nil

          timestamps.each do |timestamp|
            condition = @source_redis.get("#{entity_name}:#{check_name}:#{timestamp}:state")
            summary   = @source_redis.get("#{entity_name}:#{check_name}:#{timestamp}:summary")
            details   = @source_redis.get("#{entity_name}:#{check_name}:#{timestamp}:details")
            count     = @source_redis.get("#{entity_name}:#{check_name}:#{timestamp}:count")

            state = Flapjack::Data::State.new(:condition => condition,
              :created_at => timestamp, :updated_at => timestamp,
              :summary => summary, :details => details)
            # TODO perfdata ?
            state.save
            raise state.errors.full_messages.join(", ") unless state.persisted?

            if Flapjack::Data::Condition.healthy?(condition)
              most_severe = nil
            elsif Flapjack::Data::Condition.unhealthy.has_key?(condition) &&
              (most_severe.nil? ||
               (Flapjack::Data::Condition.unhealthy[condition] <
                  Flapjack::Data::Condition.unhealthy[most_severe.condition]))

              most_severe = state
            end

            notif_state = 'ok'.eql?(condition) ? :recovery : condition.to_sym

            if timestamp.to_i == last_notifications[notif_state]
              check.last_notifications << state
            end

            check.states << state
          end

          unless most_severe.nil?
            check.most_severe = most_severe
          end
        end
      end

      # depends on checks
      def migrate_actions
        timestamp_keys = @source_redis.keys('*:*:actions')
        timestamp_keys.each do |timestamp_key|
          # TODO fix regex, check current code
          raise "Bad regex" unless timestamp_key =~ /\A(#{ENTITY_PATTERN_FRAGMENT}):(#{CHECK_PATTERN_FRAGMENT}):actions\z/

          entity_name = $1
          check_name  = $2

          check = find_check(entity_name, check_name)

          # TODO pagination
          timestamps = @source_redis.hgetall(timestamp_key)

          timestamps.each_pair do |timestamp, action|
            # action = Flapjack::Data::Action.new(:action => action,
            #   :timestamp => timestamp)
            # action.save
            # raise action.errors.full_messages.join(", ") unless action.persisted?

            # check.actions << action
          end
        end
      end

      # depends on checks
      def migrate_scheduled_maintenances

        sm_keys = @source_redis.keys('*:*:scheduled_maintenances')

        sm_keys.each do |sm_key|
          # TODO fix regex, check current code
          unless sm_key =~ /\A(#{ENTITY_PATTERN_FRAGMENT}):(#{CHECK_PATTERN_FRAGMENT}):scheduled_maintenances\z/
            raise "Bad regex"
          end

          entity_name = $1
          check_name  = $2

          check = find_check(entity_name, check_name)

          # TODO pagination
          sched_maints = @source_redis.zrange(sm_key, 0, -1, :with_scores => true)

          sched_maints.each do |duration_timestamp|
            duration  = duration_timestamp[0].to_i
            timestamp = duration_timestamp[1].to_i

            summary = @source_redis.get("#{entity_name}:#{check_name}:#{timestamp}:scheduled_maintenance:summary")

            sched_maint = Flapjack::Data::ScheduledMaintenance.new(:start_time => timestamp,
              :end_time => (timestamp + duration), :summary => summary)
            sched_maint.save
            raise sched_maint.errors.full_messages.join(", ") unless sched_maint.persisted?

            check.scheduled_maintenances_by_start << sched_maint
            check.scheduled_maintenances_by_end << sched_maint
          end
        end
      end

      # depends on checks
      def migrate_unscheduled_maintenances
        usm_keys = @source_redis.keys('*:*:unscheduled_maintenances')

        usm_keys.each do |usm_key|
          # TODO fix regex, check current code
          unless usm_key =~ /\A(#{ENTITY_PATTERN_FRAGMENT}):(#{CHECK_PATTERN_FRAGMENT}):unscheduled_maintenances\z/
            raise "Bad regex"
          end

          entity_name = $1
          check_name  = $2

          check = find_check(entity_name, check_name)

          # # have to get them all upfront, as they're in a Redis list -- can't detect
          # # presence of single member
          # check_ack_notifications = @source_redis.
          #   lrange("#{entity_name}:#{check_name}:acknowledgement_notifications", 0, -1)

          # TODO pagination
          unsched_maints = @source_redis.zrange(usm_key, 0, -1, :with_scores => true)

          unsched_maints.each do |duration_timestamp|
            duration  = duration_timestamp[0].to_i
            timestamp = duration_timestamp[1].to_i

            summary = @source_redis.get("#{entity_name}:#{check_name}:#{timestamp}:unscheduled_maintenance:summary")

            unsched_maint = Flapjack::Data::UnscheduledMaintenance.new(:start_time => timestamp,
              :end_time => (timestamp + duration), :summary => summary)
            unsched_maint.save
            raise unsched_maint.errors.full_messages.join(", ") unless unsched_maint.persisted?

            check.unscheduled_maintenances_by_start << unsched_maint
            check.unscheduled_maintenances_by_end << unsched_maint
          end
        end
      end

      # depends on contacts, media, checks
      def migrate_rules
        notification_rules_keys = @source_redis.keys('contact_notification_rules:*')

        contact_counts_by_id = {}
        check_counts_by_id = {}

        notification_rules_keys.each do |notification_rules_key|

          raise "Bad regex for '#{notification_rules_key}'" unless
            notification_rules_key =~ /\Acontact_notification_rules:(#{ID_PATTERN_FRAGMENT})\z/

          contact_id = $1

          contact = find_contact(contact_id)

          contact_num = contact_counts_by_id[contact.id]
          if contact_num.nil?
            contact_num = contact_counts_by_id.size + 1
            contact_counts_by_id[contact.id] = contact_num
          end

          check_ids = @check_ids_by_contact_id_cache[contact.id]

          rules = []

          notification_rule_ids = @source_redis.smembers(notification_rules_key)

          notification_rule_ids.each do |notification_rule_id|

            notification_rule_data = @source_redis.hgetall("notification_rule:#{notification_rule_id}")

            time_restrictions = Flapjack.load_json(notification_rule_data['time_restrictions'])

            entities = Set.new( Flapjack.load_json(notification_rule_data['entities']))
            regex_entities = Set.new( Flapjack.load_json(notification_rule_data['regex_entities']))

            tags       = Set.new( Flapjack.load_json(notification_rule_data['tags']))
            regex_tags = Set.new( Flapjack.load_json(notification_rule_data['regex_tags']))

            # collect specific matches together with regexes
            regex_entities = regex_entities.collect {|re| Regexp.new(re) } +
              entities.to_a.collect {|entity| /\A#{Regexp.escape(entity)}\z/}
            regex_tags     = regex_tags.collect {|re| Regexp.new(re) } +
              tags.to_a.collect {|tag| /\A#{Regexp.escape(tag)}\z/}

            media_states = {}

            Flapjack::Data::Condition.unhealthy.keys.each do |fail_state|
              next if !!Flapjack.load_json(notification_rule_data["#{fail_state}_blackhole"])
              media_types = Flapjack.load_json(notification_rule_data["#{fail_state}_media"])
              unless media_types.nil? || media_types.empty?
                media_types_str = media_types.sort.join("|")
                media_states[media_types_str] ||= []
                media_states[media_types_str] << fail_state
              end
            end

            media_states.each_pair do |media_types_str, fail_states|

              rule = Flapjack::Data::Rule.new
              rule.time_restrictions = time_restrictions
              rule.conditions_list   = fail_states.sort.join("|")
              rule.save

              media = media_types_str.split('|').each_with_object([]) do |media_type, memo|
                medium = contact.media.intersect(:transport => media_type).all.first
                memo << medium unless medium.nil?
              end

              rule.media.add(*media) unless media.empty?

              checks_for_rule = Flapjack::Data::Check.intersect(:id => check_ids)

              checks = if regex_entities.empty? && regex_tags.empty?
                checks_for_rule.all
              else
                # apply the entities/tag regexes as a filter
                checks_for_rule.select do |check|
                  entity_name = check.name.split(':', 2).first
                  if regex_entities.all? {|re| re === entity_name }
                    # copying logic from https://github.com/flapjack/flapjack/blob/68a3fd1144a0aa516cf53e8ae5cb83916f78dd94/lib/flapjack/data/notification_rule.rb
                    # not sure if this does what we want, but it's how it currently works
                    matching_re = []
                    check_tags.each do |check_tags|
                      matching_re += regex_tags.select {|re| re === check_tag }
                    end
                    matching_re.size >= regex_tags.size
                  else
                    false
                  end
                end
              end

              tags = checks.collect do |check|

                check_num = check_counts_by_id[check.id]
                if check_num.nil?
                  check_num = check_counts_by_id.size + 1
                  check_counts_by_id[check.id] = check_num
                end

                tag = Flapjack::Data::Tag.new(:name => "migrated-contact_#{contact_num}-check_#{check_num}|")
                tag.save
                check.tags << tag
                tag
              end

              rule.tags.add(*tags) unless tags.empty?
              rules << rule
            end
          end

          contact.rules.add(*rules)
        end
      end

      # ###########################################################################

      def find_contact(old_contact_id)
        new_contact_id = @contact_id_cache[old_contact_id]
        return if new_contact_id.nil?

        contact = Flapjack::Data::Contact.find_by_id(new_contact_id)
        raise "No contact found for old id '#{old_contact_id}', new id '#{new_contact_id}'" if contact.nil?

        contact
      end

      def find_check(entity_name, check_name, opts = {})
        new_check_name = "#{entity_name}:#{check_name}"
        check = @check_name_cache[new_check_name]

        if check.nil? && opts[:create]
          # check doesn't already exist
          check = Flapjack::Data::Check.new(:name => check_name)
          check.save
          raise check.errors.full_messages.join(", ") unless check.persisted?
          @check_name_cache[new_check_name] = check
        end

        check
      end

      def find_tag(tag_name, opts = {})
        tag = @tag_name_cache[tag_name]

        if tag.nil? && opts[:create]
          tag = Flapjack::Data::Tag.new(:name => tag_name)
          tag.save
          raise tag.errors.full_messages.join(", ") unless tag.persisted?
          @tag_name_cache[tag_name] = tag
        end

        tag
      end

    end
  end
end

desc 'Flapjack mass data migration'
command :migrate do |migrate|

  # NB: will always assume latest released 1.x version
  migrate.desc 'Migrate Flapjack data from v1.6.0 to 2.0'
  migrate.command :to_v2 do |to_v2|

    to_v2.flag [:s, :source], :desc => 'Source Redis server URL e.g. ' \
      'redis://localhost:6379/0 (defaults to value from Flapjack configuration)'

    to_v2.flag [:d, :destination], :desc => 'Destination Redis server URL ' \
      'e.g. redis://localhost:6379/1', :required => true

    to_v2.switch [:f, :force], :desc => 'Clears the destination database on start',
      :default_value => false

    to_v2.switch 'yes-i-know-its-not-finished', :desc => 'Required switch until final v2 release',
      :default_value => false, :negatable => false

    to_v2.action do |global_options,options,args|
      migrator = Flapjack::CLI::Migrate.new(global_options, options)
      migrator.to_v2
    end
  end
end
