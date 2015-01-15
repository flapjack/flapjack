#!/usr/bin/env ruby

# Migration script, from v1 to v2 data
#
# Assumes no Flapjack instances running on source or destination DB.
# Currently assumes an empty event queue (although could maybe copy data over?).
# Currently assumes empty notification queues (although could maybe convert?).
#
# to see the state of the redis databases before and after, e.g. (using nodejs
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
require 'sandstorm'

require 'flapjack'
require 'flapjack/data/condition'
require 'flapjack/data/check'
require 'flapjack/data/entry'
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

        @config = Flapjack::Configuration.new
        @config.load(global_options[:config])
        @config_env = @config.all

        @source_redis_options = @config.for_redis
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
        dest_redis = Redis.new(:url => source_addr, :driver => :hiredis)

        Sandstorm.redis = dest_redis

        dest_db_size = Sandstorm.redis.dbsize
        if dest_db_size > 0
          if options[:force]
            Sandstorm.redis.flushdb
            puts "Cleared #{@options[:destination]} db"
          else
            exit_now! "Destination db #{@options[:destination]} has " \
              "#{dest_db_size} keys, and the --force option was not provided"
          end
        end

        # key is old contact_id, value = new contact id
        @contact_id_cache = {}

        # key is entity_name:check_name, value is sandstorm record
        @check_name_cache = {}

        # key is tag name, value is sandstorm record
        @tag_name_cache = {}

        # cache old entity/check <-> contact linkage, use as limiting set in
        # rule construction
        @check_ids_by_contact_id_cache = {}


        migrate_contacts_and_media
        migrate_checks

        migrate_contact_entity_linkages

        migrate_rules # only partially done

        migrate_states
        migrate_actions  # only partially done

        migrate_scheduled_maintenances
        migrate_unscheduled_maintenances # TODO notification data into entries?

        # migrate_notification_blocks
        # migrate_alerting_checks
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

          # skipped contact tags (dropped) and pagerduty media (moved to gateway config)

          contact = Flapjack::Data::Contact.new(:name =>
              "#{contact_data['first_name']} #{contact_data['last_name']}",
            :timezone => timezone)
          contact.save
          raise contact.errors.full_messages.join(", ") unless contact.persisted?

          media_addresses.each_pair do |media_type, address|
            medium = Flapjack::Data::Medium.new(:transport => media_transport,
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

            # TODO do we want tag namespacing?
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
            check_ids_by_contact_id_cache[contact.id] ||= []
          end

          tag_for_check = proc do |en, cn, tn|
            check = find_check(en, cn)
            check.tags << find_tag(tn, :create => true)

            contacts.each do |contact|
              check_ids_by_contact_id_cache[contact.id] << check.id
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

          timestamps.each do |timestamp|
            condition = @source_redis.get("#{entity_name}:#{check_name}:#{timestamp}:state")
            summary   = @source_redis.get("#{entity_name}:#{check_name}:#{timestamp}:summary")
            details   = @source_redis.get("#{entity_name}:#{check_name}:#{timestamp}:details")
            count     = @source_redis.get("#{entity_name}:#{check_name}:#{timestamp}:count")

            state = Flapjack::Data::State.new(:condition => condition,
              :timestamp => timestamp)
            state.save
            raise state.errors.full_messages.join(", ") unless state.persisted?

            entry = Flapjack::Data::Entry.new(:timestamp => timestamp,
              :condition => condition, :summary => summary, :details => details)
            # TODO perfdata ?
            entry.save
            raise entry.errors.full_messages.join(", ") unless entry.persisted?

            state.entries << entry

            check.states << state
          end
        end

        # TODO foreach check, work out most_severe state and the various last_notifications
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

        notification_rules_keys.each do |notification_rules_key|

          raise "Bad regex for '#{notification_rules_key}'" unless
            notification_rules_key =~ /\Acontact_notification_rules:(#{ID_PATTERN_FRAGMENT})\z/

          contact_id = $1

          contact = find_contact(contact_id)

          rules = []

          notification_rule_ids = @source_redis.smembers(notification_rules_key)

          notification_rule_ids.each do |notification_rule_id|

            notification_rule_data = @source_redis.hgetall("notification_rule:#{notification_rule_id}")

            # TODO for all rules created, add tags based on the various entity & tags attrs,
            # and also set those on matching checks

            time_restrictions = Flapjack.load_json(notification_rule_data['time_restrictions'])

            # entities = Set.new( Flapjack.load_json(notification_rule_data['entities']))
            # tags     = Set.new( Flapjack.load_json(notification_rule_data['tags']))

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

              media = media_types_str.split('|').inject([]) do |memo, media_type|
                medium = contact.media.intersect(:transport => media_type).all.first
                raise "Couldn't find media #{media_type} for contact old_id #{contact_id}" if medium.nil?
                memo += medium
                memo
              end

              rule.media.add(*media) unless media.empty?

              # TODO if all rule entities/tags fields are empty, create a tag that
              # links the rule to all checks for entities that were registered for
              # the contact -- otherwise apply the entities/tag fields as a filter

              rules << rule
            end
          end

          contact.rules.add(*rules)
        end
      end

# # depends on contacts, media, checks
# def migrate_notification_blocks
#   # drop_alerts_for_contact:CONTACT_ID:MEDIA:ENTITY:CHECK:STATE
#   nb_keys = @source_redis.keys('drop_alerts_for_contact:*:*:*:*:*')

#   nb_keys.each do |nb_key|

#     # TODO fix regex, check current code
#     raise "Bad regex" unless nb_key =~ /\Adrop_alerts_for_contact:(#{ID_PATTERN_FRAGMENT}):(\w+):(#{ENTITY_PATTERN_FRAGMENT}):(#{CHECK_PATTERN_FRAGMENT}):(\w+)\z/

#     contact_id  = $1
#     media_type  = $2
#     entity_name = $3
#     check_name  = $4
#     state       = $5

#     # TODO Lua script for full timestamp back from Redis -- less fuzzy
#     expiry_time = Time.now + @source_redis.ttl(nb_key)

#     medium  = find_medum(contact_id, media_type)
#     check   = find_or_create_check(entity_name, check_name)

#     notification_block = Flapjack::Data::NotificationBlock.new(
#       :expire_at => expiry_time, :rollup => false, :state => state)

#     notification_block.save
#     raise notification_block.errors.full_messages.join(", ") unless notification_block.persisted?

#     check.notification_blocks  << notification_block
#     medium.notification_blocks << notification_block
#   end

#   rnb_keys = @source_redis.keys('drop_rollup_alerts_for_contact:*:*')

#   rnb_keys.each do |rnb_key|

#     # TODO fix regex, check current code
#     raise "Bad regex" unless rnb_key =~ /\Adrop_rollup_alerts_for_contact:(#{ID_PATTERN_FRAGMENT}):(\w+)\z/

#     contact_id  = $1
#     media_type  = $2

#     # TODO Lua script for full timestamp back from Redis -- less fuzzy
#     expiry_time = Time.now + @source_redis.ttl(rnb_key)

#     medium = find_medum(contact_id, media_type)

#     rollup_notification_block = Flapjack::Data::NotificationBlock.new(
#       :expire_at => expiry_time, :rollup => true)
#     rollup_notification_block.save
#     raise rollup_notification_block.errors.full_messages.join(", ") unless rollup_notification_block.persisted?

#     medium.notification_blocks << notification_block
#   end

# end

# # depends on contacts, media, checks
# def migrate_alerting_checks

#   alerting_checks_keys = @source_redis.keys('contact_alerting_checks:*:media:*')

#   alerting_checks_keys.each do |alerting_checks_key|

#     raise "Bad regex" unless alerting_checks_key =~ /\Acontact_alerting_checks:(#{ID_PATTERN_FRAGMENT}):media:(\w+)\z/

#     contact_id = $1
#     media_type = $2

#     medium = find_medum(contact_id, media_type)

#     contact_medium_checks = @source_redis.zrange(alerting_checks_key, 0, -1)

#     contact_medium_checks.each do |entity_and_check_name|
#       entity_name, check_name = entity_and_check_name.split(':', 1)
#       check = find_or_create_check(entity_name, check_name)

#       medium.alerting_checks << check
#     end
#   end
# end

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
  migrate.desc 'Migrate Flapjack data from v1.2.1 to 2.0'
  migrate.command :to_v2 do |to_v2|

    to_v2.flag [:s, 'source'], :desc => 'Source Redis server URL e.g. ' \
      'redis://localhost:6379/0 (defaults to value from Flapjack configuration)'

    to_v2.flag [:d, 'destination'], :desc => 'Destination Redis server URL ' \
      'e.g. redis://localhost:6379/1', :required => true

    to_v2.switch [:f, 'force'], :desc => 'Clears the destination database on start',
      :default_value => false

    to_v2.action do |global_options,options,args|
      migrator = Flapjack::CLI::Migrate.new(global_options, options)
      migrator.to_v2
    end
  end
end
