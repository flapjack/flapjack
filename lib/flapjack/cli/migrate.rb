#!/usr/bin/env ruby

# Migration script, from v1 to v2 data
#
# Assumes no Flapjack instances running on source or destination DB. Also
# assumes an empty event queue and empty notification queues; best to run an
# instance of Flapjack v1 with the processor disabled to drain out notifications
# prior to running this.

# To see the state of the redis databases before and after, e.g. (using nodejs
# 'npm install redis-dump -g')
#
#  be ruby bin/flapjack migrate to_v2 --source=redis://127.0.0.1/7 --destination=redis://127.0.0.1/8
#  redis-dump -d 7 >~/Desktop/dump7.txt && redis-dump -d 8 >~/Desktop/dump8.txt
#
#   Not migrated:
#      current alertable/rollup status (these should reset on app start)
#      notifications/alerts (see note above)

ENTITY_PATTERN_FRAGMENT = '[a-zA-Z0-9][a-zA-Z0-9\.\-_]*[a-zA-Z0-9]'
CHECK_PATTERN_FRAGMENT  = '.+'
ID_PATTERN_FRAGMENT     = '.+'
TAG_PATTERN_FRAGMENT    = '.+'

# silence deprecation warning
require 'i18n'
I18n.config.enforce_available_locales = true

require 'redis'
require 'hiredis'
require 'ice_cube'
require 'zermelo'

require 'flapjack'
require 'flapjack/data/condition'
require 'flapjack/data/check'
require 'flapjack/data/state'
require 'flapjack/data/contact'
require 'flapjack/data/medium'
require 'flapjack/data/rule'
require 'flapjack/data/scheduled_maintenance'
require 'flapjack/data/unscheduled_maintenance'
require 'flapjack/data/tag'

require 'flapjack/utility'

module Flapjack
  module CLI
    class Migrate

      include Flapjack::Utility

      def initialize(global_options, options)
        @global_options = global_options
        @options = options

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

        @source_redis_version = @source_redis.info['redis_version']

        dest_addr = @options[:destination]
        dest_redis = Redis.new(:url => dest_addr, :driver => :hiredis)

        # Zermelo.logger = ::Logger.new('/tmp/zermelo_migrate.log')

        do_rule_migration = @options[:rules]

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

        @current_entity_names = @source_redis.zrange('current_entities', 0, -1)
        @current_check_names = source_keys_matching('current_checks:?*')

        @time = Time.now

        puts "#{Time.now.iso8601} Migrating contacts and media"
        migrate_contacts_and_media

        puts "#{Time.now.iso8601} Migrating checks"
        migrate_checks

        puts "Migrating check states & actions"
        Flapjack::Data::Check.lock(
          Flapjack::Data::State,
          Flapjack::Data::ScheduledMaintenance,
          Flapjack::Data::UnscheduledMaintenance
        ) do

          idx = 0
          check_count = Flapjack::Data::Check.count

          Flapjack::Data::Check.sort(:name).each do |check|
            idx += 1
            puts "#{Time.now.iso8601} #{idx}/#{check_count} #{check.name}"
            migrate_states(check)
            migrate_actions(check)
            migrate_scheduled_maintenances(check)
            migrate_unscheduled_maintenances(check)

            if (idx % 500) == 0
              # reopen connections -- avoid potential timeout for long-running jobs
              @source_redis.quit
              @source_redis = case source_addr
              when Hash
                Redis.new(source_addr.merge(:driver => :hiredis))
              when String
                Redis.new(:url => source_addr, :driver => :hiredis)
              end

              Zermelo.redis.quit
              Zermelo.redis = Redis.new(:url => dest_addr, :driver => :hiredis)
            end
          end
        end

        if do_rule_migration
          puts "#{Time.now.iso8601} Migrating contact/entity linkages"
          migrate_contact_entity_linkages

          puts "#{Time.now.iso8601} Migrating rules"
          migrate_rules
        end

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
        source_keys_matching('contact:?*').each do |contact_key|
          contact_key =~ /\Acontact:(#{ID_PATTERN_FRAGMENT})\z/
          contact_id = Regexp.last_match(1)
          raise "Bad regex for '#{contact_key}'" if contact_id.nil?

          contact_data = @source_redis.hgetall(contact_key).merge(:id => contact_id)

          timezone = @source_redis.get("contact_tz:#{contact_id}")

          media_addresses = @source_redis.hgetall("contact_media:#{contact_id}")
          media_intervals = @source_redis.hgetall("contact_media_intervals:#{contact_id}")
          media_rollup_thresholds = @source_redis.hgetall("contact_media_rollup_thresholds:#{contact_id}")

          contact = Flapjack::Data::Contact.new(:name =>
              "#{contact_data['first_name']} #{contact_data['last_name']}",
            :timezone => timezone)
          if contact.valid?
            contact.save
          else
            puts "Invalid contact: #{contact.errors.full_messages.join(", ")}  #{contact.inspect}"
            next
          end

          media_addresses.each_pair do |media_type, address|
            medium_data = if 'pagerduty'.eql?(media_type)
              pagerduty_credentials =
                @source_redis.hgetall("contact_pagerduty:#{contact_id}")

              {
                :transport => 'pagerduty',
                :address => address,
                :pagerduty_subdomain => pagerduty_credentials['subdomain'],
                :pagerduty_token => pagerduty_credentials['token'],
                :pagerduty_ack_duration => nil
              }
            else
              rut = media_rollup_thresholds[media_type]
              {
                :transport => media_type,
                :address => address,
                :interval => media_intervals[media_type].to_i,
                :rollup_threshold => rut.nil? ? nil : rut.to_i
              }
            end

            medium = Flapjack::Data::Medium.new(medium_data)
            if medium.valid?
              medium.save
              contact.media << medium
            else
              puts "Invalid medium: #{medium.errors.full_messages.join(", ")}  #{medium.inspect}"
            end
          end

          @contact_id_cache[contact_id] = contact.id
        end
      end

      def migrate_checks
        all_entity_names_by_id = @source_redis.hgetall('all_entity_names_by_id')

        entity_tags_by_entity_name = {}

        source_keys_matching('entity_tag:?*').each do |entity_tag_key|
          entity_tag_key =~ /\Aentity_tag:(#{TAG_PATTERN_FRAGMENT})\z/
          entity_tag = Regexp.last_match(1)
          raise "Bad regex for '#{entity_tag_key}'" if entity_tag.nil?

          entity_ids = @source_redis.smembers(entity_tag_key)

          entity_ids.each do |entity_id|
            entity_name = all_entity_names_by_id[entity_id]
            raise "No entity name for id #{entity_id}" if entity_name.nil? || entity_name.empty?

            entity_tags_by_entity_name[entity_name] ||= []
            entity_tags_by_entity_name[entity_name] << entity_tag
          end
        end

        source_keys_matching("all_checks:?*") do |all_checks_key|
          all_checks_key =~ /\Aall_checks:(#{ENTITY_PATTERN_FRAGMENT})\z/

          entity_name = Regexp.last_match(1)
          raise "Bad regex for '#{all_checks_key}'" if entity_name.nil?

          entity_tags = entity_tags_by_entity_name[entity_name]

          all_check_names     = @source_redis.zrange(all_checks_key, 0, -1).reject {|k| k.empty? }
          current_check_names = @source_redis.zrange("current_checks:#{entity_name}", 0, -1)

          all_check_names.each do |check_name|
            check = find_check(entity_name, check_name, :create => true)
            check.enabled = current_check_names.include?(check_name)
            check.save
            raise check.errors.full_messages.join(", ") unless check.persisted?

            check.tags << find_tag("entity_#{entity_name}", :create => true)

            unless entity_tags.nil? || entity_tags.empty?
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
        all_entity_names_by_id = @source_redis.hgetall('all_entity_names_by_id')

        source_keys_matching('contacts_for:?*').each do |contacts_for_key|

          contacts_for_key =~ /\Acontacts_for:(#{ID_PATTERN_FRAGMENT})(?::(#{CHECK_PATTERN_FRAGMENT}))?\z/
          entity_id   = Regexp.last_match(1)
          check_name  = Regexp.last_match(2)
          if entity_id.nil?
            raise "Bad regex for '#{contacts_for_key}'"
          end

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
            all_checks_for_entity.each do |cn|
              next if cn.empty?
              tag_for_check.call(entity_name, cn, tag_name)
            end
          else
            # interested in check
            tag_for_check.call(entity_name, check_name,
              "check_#{entity_name}:#{check_name}")
          end
        end
      end

      # depends on checks
      def migrate_states(check)
        states_key = "#{check.name}:states"
        return unless @source_redis.exists(states_key)

        last_notification_types = %w(warning critical unknown recovery
                                     acknowledgement)

        ln_keys = last_notification_types.map {|t| "#{check.name}:last_#{t}_notification" }
        ln_data = @source_redis.mget(*ln_keys)
        last_notifications = Hash[ *(last_notification_types.map(&:to_sym).zip(ln_data).flatten(1)) ]

        current_condition = nil
        most_severe = nil

        states_to_add = []

        paginate_action(:list, 100, states_key) do |timestamp|
          ect = "#{check.name}:#{timestamp}"
          ts_keys = %w(state summary details count perfdata).map {|k| "#{ect}:#{k}"}
          condition, summary, details, count, perfdata_json =
            @source_redis.mget(*ts_keys)

          current_condition = condition unless condition.nil?

          timestamp_i = timestamp.to_i

          state = Flapjack::Data::State.new(
            :condition => current_condition,
            :created_at => timestamp_i,
            :updated_at => timestamp_i,
            :summary => summary,
            :details => details,
            :perfdata_json => perfdata_json
          )
          raise state.errors.full_messages.join(", ") unless state.valid?

          unless condition.nil?
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
              check.latest_notifications << state
            end
          end

          states_to_add << state
        end

        unless states_to_add.empty?
          states_to_add.map(&:save)
          check.states.add(*states_to_add)

          unless current_condition.nil?
            check.condition = current_condition
            check.failing = !Flapjack::Data::Condition.healthy?(current_condition)
            if check.valid?
              check.save
            else
              puts "Invalid check: #{check.errors.full_messages.join(", ")}  #{check.inspect}"
            end
          end

          unless most_severe.nil?
            check.most_severe = most_severe
          end
        end
      end

      # depends on checks, states
      def migrate_actions(check)
        actions_key = "#{check.name}:actions"
        return unless @source_redis.exists(actions_key)

        states_to_add = []

        paginate_action(:hash, 100, actions_key) do |timestamp, action|
          timestamp_f = timestamp.to_f
          timestamp_i = timestamp.to_i

          start_range = Zermelo::Filters::IndexRange.new(nil, timestamp_f, :by_score => true)
          previous_state = check.states.intersect(:created_at => start_range).last
          previous_cond = previous_state.nil? ? nil : previous_state.condition

          state = Flapjack::Data::State.new(
            :action => action,
            :condition  => previous_cond,
            :created_at => timestamp_i,
            :updated_at => timestamp_i
          )

          raise state.errors.full_messages.join(", ") unless state.valid?
          states_to_add << state
        end

        return if states_to_add.empty?
        states_to_add.map(&:save)
        check.states.add(*states_to_add)
      end

      # depends on checks
      def migrate_scheduled_maintenances(check)
        sm_key = "#{check.name}:scheduled_maintenances"
        return unless @source_redis.exists(sm_key)

        sched_maints_to_add = []

        paginate_action(:zset, 100, sm_key) do |timestamp, duration|
          timestamp_i = timestamp.to_i
          duration_i  = duration.to_i

          summary = @source_redis.get("#{check.name}:#{timestamp}:scheduled_maintenance:summary")

          sched_maint = Flapjack::Data::ScheduledMaintenance.new(
            :start_time => timestamp_i,
            :end_time => timestamp_i + duration_i,
            :summary => summary
          )

          if sched_maint.valid?
            sched_maints_to_add << sched_maint
          else
            puts "Invalid scheduled maintenance: #{sched_maint.errors.full_messages.join(", ")}  #{sched_maint.inspect}"
          end
        end

        return if sched_maints_to_add.empty?
        sched_maints_to_add.map(&:save)
        check.scheduled_maintenances.add(*sched_maints_to_add)
      end

      # depends on checks
      def migrate_unscheduled_maintenances(check)
        usm_key = "#{check.name}:unscheduled_maintenances"
        return unless @source_redis.exists(usm_key)

        unsched_maints_to_add = []

        paginate_action(:zset, 100, usm_key) do |timestamp, duration|
          timestamp_i = timestamp.to_i
          duration_i  = duration.to_i

          summary = @source_redis.get("#{check.name}:#{timestamp}:unscheduled_maintenance:summary")

          unsched_maint = Flapjack::Data::UnscheduledMaintenance.new(
            :start_time => timestamp_i,
            :end_time => timestamp_i + duration_i,
            :summary => summary
          )

          if unsched_maint.valid?
            unsched_maints_to_add << unsched_maint
          else
            puts "Invalid unscheduled maintenance: #{unsched_maint.errors.full_messages.join(", ")}  #{unsched_maint.inspect}"
          end
        end

        return if unsched_maints_to_add.empty?
        unsched_maints_to_add.map(&:save)
        check.unscheduled_maintenances.add(*unsched_maints_to_add)
      end

      def field_from_rule_json(rule, field)
        field_json = rule[field]
        return if field_json.nil? || field_json.empty?
        Flapjack.load_json(field_json)
      end

      # depends on contacts, media, checks
      def migrate_rules
        contact_counts_by_id = {}
        check_counts_by_id = {}

        source_keys_matching('contact_notification_rules:?*').each do |rules_key|

          rules_key =~ /\Acontact_notification_rules:(#{ID_PATTERN_FRAGMENT})\z/
          contact_id = Regexp.last_match(1)
          raise "Bad regex for '#{rules_key}'" if contact_id.nil?

          contact = find_contact(contact_id)

          contact_num = contact_counts_by_id[contact.id]
          if contact_num.nil?
            contact_num = contact_counts_by_id.size + 1
            contact_counts_by_id[contact.id] = contact_num
          end

          check_ids = @check_ids_by_contact_id_cache[contact.id]

          Flapjack::Data::Rule.lock(
            Flapjack::Data::Check,
            Flapjack::Data::Tag,
            Flapjack::Data::Contact,
            Flapjack::Data::Medium
          ) do

            new_rule_ids = []

            rule_ids = @source_redis.smembers(rules_key)
            rule_ids.each do |rule_id|
              rule_data = @source_redis.hgetall("notification_rule:#{rule_id}")

              old_time_restrictions_json = rule_data['time_restrictions']

              time_restrictions = if old_time_restrictions_json.nil? || old_time_restrictions_json.empty?
                 nil
              else
                old_time_restrictions = Flapjack.load_json(old_time_restrictions_json)
                if old_time_restrictions.nil? || old_time_restrictions.empty?
                  []
                elsif old_time_restrictions.is_a?(Hash)
                  [rule_time_restriction_to_icecube_schedule(old_time_restrictions, contact.time_zone)]
                elsif old_time_restrictions.is_a?(Array)
                  old_time_restrictions.map {|t| rule_time_restriction_to_icecube_schedule(t, contact.time_zone)}
                end
              end

              filter_tag_ids = Set.new

              old_entities = field_from_rule_json(rule_data, 'entities')
              entity_names = case old_entities
              when String
                Set.new([old_entities])
              when Array
                Set.new(old_entities)
              else
                nil
              end

              old_regex_entities = field_from_rule_json(rule_data, 'regex_entities')
              entity_regexes = case old_regex_entities
              when String
                Set.new([Regexp.new(old_regex_entities)])
              when Array
                Set.new(old_regex_entities.map {|re| Regexp.new(re) })
              else
                nil
              end

              Flapjack::Data::Tag.intersect(:name => '/^manage_service_\d+_.+$/').each do |tag|
                next if tag.name.nil? ||
                  (tag.name !~ /^manage_service_(\d+)_(.+)$/)
                # eldest_service_id = Regexp.last_match(1)
                service_name = Regexp.last_match(2)

                next unless entity_names.include?(service_name) ||
                  entity_regexes.all? {|re| !re.match(service_name).nil? }
                filter_tag_ids << tag.id
              end


              old_tags = field_from_rule_json(rule_data, 'tags')
              tags = case old_tags
              when String
                Set.new([old_tags])
              when Array
                Set.new(old_tags)
              else
                nil
              end

              old_regex_tags = field_from_rule_json(rule_data, 'regex_tags')
              tag_regexes = case old_regex_tags
              when String
                Set.new([Regexp.new(old_regex_tags)])
              when Array
                Set.new(old_regex_tags.map {|re| Regexp.new(re) })
              else
                nil
              end

              # start with the initial limited visibility range (overall scope)
              old_tags_checks = Flapjack::Data::Check.intersect(:id => check_ids)

              # then limit further by checks with names containing tag words
              unless tags.nil? || tags.empty?
                old_tags_checks = tags.inject(old_tags_checks) do |memo, tag|
                  memo.intersect(:name => /(?: |^)#{Regexp.escape(tag)}(?: |$)/)
                end
              end

              # and by checks with names matching regexes
              unless tag_regexes.nil? || tag_regexes.empty?
                old_tags_checks = tag_regexes.inject(old_tags_checks) do |memo, tag_regex|
                  memo.intersect(:name => /#{tag_regex}/)
                end
              end

              unless old_tags_checks.empty?
                tag = Flapjack::Data::Tag.new(:name => "migrated_rule_#{rule_id}")
                tag.save!
                tag.checks.add_ids(*old_tags_checks.ids)
                filter_tag_ids << tag.id
              end

              normal_rules_to_create = []
              filter_rules_to_create = []

              conditions_by_blackhole_and_media = {false => {},
                                                   true => {}}

              Flapjack::Data::Condition.unhealthy.keys.each do |fail_state|
                media_types = Flapjack.load_json(rule_data["#{fail_state}_media"])
                next if media_types.nil? || media_types.empty?

                media_types_str = media_types.sort.join("|")
                blackhole = !!Flapjack.load_json(rule_data["#{fail_state}_blackhole"])
                conditions_by_blackhole_and_media[blackhole][media_types_str] ||= []
                conditions_by_blackhole_and_media[blackhole][media_types_str] << fail_state
              end

              # multiplier -- conditions_by_blackhole_and_media[false].size +
              #               conditions_by_blackhole_and_media[true].size

              [false, true].each do |blackhole|
                 normal_rules_to_create += conditions_by_blackhole_and_media[blackhole].each_with_object([]) do |(media_types_str, fail_states), memo|
                  media_types = media_types_str.split('|')

                  rule_media_ids = contact.media.intersect(:transport => media_types).ids
                  # if no media to communicate by, don't save the rule
                  next if rule_media_ids.empty?

                  memo << {
                    :enabled         => true,
                    :blackhole       => blackhole,
                    :strategy        => 'global', # filter rule also applies
                    :conditions_list => fail_states.sort.join(','),
                    :medium_ids      => rule_media_ids
                  }
                end
              end

              # multiply by number of applied time restrictions, if any
              unless time_restrictions.empty?
                replace_rules = time_restrictions.each_with_object([]) do |tr, memo|
                  memo += normal_rules_to_create.collect do |r|
                    r.merge(:time_restriction => tr)
                  end
                end

                normal_rules_to_create = replace_rules
              end

              unless filter_tag_ids.empty?
                filter_data = {
                  :blackhole => true,
                  :strategy => 'no_tag'
                }

                filter_rules = normal_rules_to_create.each_with_object([]) do |r, memo|
                  memo << r.merge(filter_data) unless r[:blackhole]
                end

                filter_rules_to_create += filter_rules
              end

              new_rule_ids += normal_rules_to_create.collect do |r|
                new_rule_id = SecureRandom.uuid
                r[:id] = new_rule_id
                medium_ids = r.delete(:medium_ids)
                rule = Flapjack::Data::Rule.new(r)
                rule.save!
                rule.media.add_ids(*medium_ids)
                new_rule_id
              end

              new_rule_ids += filter_rules_to_create.collect do |r|
                new_rule_id = SecureRandom.uuid
                r[:id] = new_rule_id
                medium_ids = r.delete(:medium_ids)
                rule = Flapjack::Data::Rule.new(r)
                rule.save!
                rule.media.add_ids(*medium_ids)
                rule.tags.add_ids(*filter_tag_ids) unless filter_tag_ids.empty?
                new_rule_id
              end
            end

            contact.rules.add_ids(*new_rule_ids) unless new_rule_ids.empty?
          end
        end
      end

      # # ###########################################################################

      def source_keys_matching(key_pat, &block)
        if (@source_redis_version.split('.') <=> ['2', '8', '0']) == 1
          @source_redis.scan_each(:match => key_pat, &block)
        else
          @source_redis.keys(key_pat).each {|k| block.call(k) }
        end
      end

      def paginate_action(type, per_page, key, &block)
        if ((@source_redis_version.split('.') <=> ['2', '8', '0']) == 1) && [:hash, :zset].include?(type)
          case type
          when :hash
            @source_redis.hscan_each(key, :count => per_page, &block)
          when :zset
            @source_redis.zscan_each(key, :count => per_page, &block)
          end
        else
          total = case type
          when :hash
            @source_redis.hlen(key)
          when :list
            @source_redis.llen(key)
          when :zset
            @source_redis.zcard(key)
          end
          return unless total > 0

          current = 0

          h_keys = @source_redis.hkeys(key) if :hash.eql?(type)

          loop do
            window_end = [current + per_page, total].min - 1
            items = case type
            when :hash
              h_key_window = h_keys[current..window_end]
              Hash[ *(@source_redis.hmget(key, *h_key_wind).flatten(1)) ]
            when :list
              @source_redis.lrange(key, current, window_end)
            when :zset
              Hash[ *(@source_redis.zrange(key, current, window_end, :with_scores => true).flatten(1)) ]
            end

            case type
            when :hash, :zset
              items.each_pair { |k, v| yield(k, v) }
            when :list
              items.each { |item| yield(item) }
            end

            current += items.size
            break if current >= total
          end
        end
      end


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

        if check.nil?
          if opts[:create]
            enabled = @current_entity_names.include?(entity_name) &&
                      @source_redis.zrange("current_checks:#{entity_name}", 0, -1).include?(check_name)
            check = Flapjack::Data::Check.new(:name => new_check_name,
              :enabled => enabled)
            check.save
            raise check.errors.full_messages.join(", ") unless check.persisted?
            # puts "adding #{new_check_name} to check cache"
            @check_name_cache[new_check_name] = check
          else
            puts "No check found for '#{new_check_name}'"
          end
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

      # NB: ice_cube doesn't have much rule data validation, and has
      # problems with infinite loops if the data can't logically match; see
      #   https://github.com/seejohnrun/ice_cube/issues/127 &
      #   https://github.com/seejohnrun/ice_cube/issues/137
      # We may want to consider some sort of timeout-based check around
      # anything that could fall into that.
      #
      # We don't want to replicate IceCube's from_hash behaviour here,
      # but we do need to apply some sanity checking on the passed data.
      def rule_time_restriction_to_icecube_schedule(tr, timezone, opts = {})
        return if tr.nil? || !tr.is_a?(Hash) ||
                  timezone.nil? || !timezone.is_a?(ActiveSupport::TimeZone)
        prepared_restrictions = rule_prepare_time_restriction(tr, timezone)
        return if prepared_restrictions.nil?
        IceCube::Schedule.from_hash(prepared_restrictions)
      rescue ArgumentError => ae
        if logger = opts[:logger]
          logger.error "Couldn't parse rule data #{e.class}: #{e.message}"
          logger.error prepared_restrictions.inspect
          logger.error e.backtrace.join("\n")
        end
        nil
      end

      def rule_prepare_time_restriction(time_restriction, timezone = nil)
        # this will hand back a 'deep' copy
        tr = symbolize(time_restriction)

        return unless (tr.has_key?(:start_time) || tr.has_key?(:start_date)) &&
          (tr.has_key?(:end_time) || tr.has_key?(:end_date))

        # exrules is deprecated in latest ice_cube, but may be stored in data
        # serialised from earlier versions of the gem
        # ( https://github.com/flapjack/flapjack/issues/715 )
        tr.delete(:exrules)

        parsed_time = proc {|tr, field|
          if t = tr.delete(field)
            t = t.dup
            t = t[:time] if t.is_a?(Hash)

            if t.is_a?(Time)
              t
            else
              begin; (timezone || Time).parse(t); rescue ArgumentError; nil; end
            end
          else
            nil
          end
        }

        start_time = parsed_time.call(tr, :start_date) || parsed_time.call(tr, :start_time)
        end_time   = parsed_time.call(tr, :end_date) || parsed_time.call(tr, :end_time)

        return unless start_time && end_time

        tr[:start_time] = timezone ?
                            {:time => start_time, :zone => timezone.name} :
                            start_time

        tr[:end_time]   = timezone ?
                            {:time => end_time, :zone => timezone.name} :
                            end_time

        tr[:duration]   = end_time - start_time

        # check that rrule types are valid IceCube rule types
        return unless tr[:rrules].is_a?(Array) &&
          tr[:rrules].all? {|rr| rr.is_a?(Hash)} &&
          (tr[:rrules].map {|rr| rr[:rule_type]} -
           ['Daily', 'Hourly', 'Minutely', 'Monthly', 'Secondly',
            'Weekly', 'Yearly']).empty?

        # rewrite Weekly to IceCube::WeeklyRule, etc
        tr[:rrules].each {|rrule|
          rrule[:rule_type] = "IceCube::#{rrule[:rule_type]}Rule"
        }

        # TODO does this need to check classes for the following values?
        # "validations": {
        #   "day": [1,2,3,4,5]
        # },
        # "interval": 1,
        # "week_start": 0

        tr
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

    to_v2.switch [:rules], :desc => 'Also migrate rules and contact/entity visibility restrictions',
      :default_value => false

    to_v2.switch [:force], :desc => "Run even if the destination DB isn't empty (clears it first)",
      :default_value => false

    to_v2.action do |global_options,options,args|
      migrator = Flapjack::CLI::Migrate.new(global_options, options)
      migrator.to_v2
    end
  end
end
