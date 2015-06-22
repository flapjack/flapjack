#!/usr/bin/env ruby

# NB: use of redis.keys probably indicates we should maintain a data
# structure to avoid the need for this type of query

require 'securerandom'
require 'set'

require 'ice_cube'

require 'flapjack/data/entity'
require 'flapjack/data/entity_check'
require 'flapjack/data/notification_rule'

module Flapjack

  module Data

    class Contact

      attr_accessor :id, :first_name, :last_name, :email, :media,
        :media_intervals, :media_rollup_thresholds, :pagerduty_credentials

      ALL_MEDIA  = [
        'email',
        'sms',
        'slack',
        'sms_twilio',
        'sms_nexmo',
        'jabber',
        'pagerduty',
        'sns'
      ]

      def self.all(options = {})
        raise "Redis connection not set" unless redis = options[:redis]

        redis.keys('contact:*').inject([]) {|ret, k|
          k =~ /^contact:(.*)$/
          id = $1
          contact = self.find_by_id(id, :redis => redis)
          ret << contact unless contact.nil?
          ret
        }.sort_by {|c| [c.last_name, c.first_name]}
      end

      def self.find_by_id(contact_id, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        raise "No id value passed" unless contact_id
        logger = options[:logger]

        # sanity check
        return unless redis.hexists("contact:#{contact_id}", 'first_name')

        contact = self.new(:id => contact_id, :redis => redis, :logger => logger)
        contact.refresh
        contact
      end

      def self.find_by_ids(contact_ids, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        logger = options[:logger]

        contact_ids.map do |id|
          self.find_by_id(id, options)
        end
      end

      def self.exists_with_id?(contact_id, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        raise "No id value passed" unless contact_id

        redis.exists("contact:#{contact_id}")
      end

      def self.add(contact_data, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        contact_id = contact_data['id']
        raise "Contact id value not provided" if contact_id.nil?

        if contact = self.find_by_id(contact_id, :redis => redis)
          contact.delete!
        end

        self.add_or_update(contact_id, contact_data, :redis => redis)
        contact = self.find_by_id(contact_id, :redis => redis)

        unless contact.nil?
          contact.notification_rules # invoke to create general rule
        end

        contact
      end

      def self.delete_all(options = {})
        raise "Redis connection not set" unless redis = options[:redis]

        self.all(:redis => redis).each do |contact|
          contact.delete!
        end
      end

      # ensure that instance variables match redis state
      # TODO may want to make this protected/private, it's only
      # used in this class
      def refresh
        fn, ln, em = @redis.hmget("contact:#{@id}", 'first_name', 'last_name', 'email')
        self.first_name = Flapjack.sanitize(fn)
        self.last_name  = Flapjack.sanitize(ln)
        self.email      = Flapjack.sanitize(em)
        self.media = @redis.hgetall("contact_media:#{@id}")
        self.media_intervals = @redis.hgetall("contact_media_intervals:#{self.id}")
        self.media_rollup_thresholds = @redis.hgetall("contact_media_rollup_thresholds:#{self.id}")

        # similar to code in instance method pagerduty_credentials
        if service_key = @redis.hget("contact_media:#{@id}", 'pagerduty')
          self.pagerduty_credentials =
            @redis.hgetall("contact_pagerduty:#{@id}").merge('service_key' => service_key)
        end
      end

      def update(contact_data)
        self.class.add_or_update(@id, contact_data, :redis => @redis)
        self.refresh
      end

      def delete!
        # remove entity & check registrations -- ugh, this will be slow.
        # rather than check if the key is present we'll just request its
        # deletion anyway, fewer round-trips
        @redis.keys('contacts_for:*').each do |cfk|
          @redis.srem(cfk, self.id)
        end

        @redis.del("drop_alerts_for_contact:#{self.id}")
        dafc = @redis.keys("drop_alerts_for_contact:#{self.id}:*")
        @redis.del(*dafc) unless dafc.empty?

        # TODO if implemented, alerts_by_contact & alerts_by_check:
        # list all alerts from all matched keys, remove them from
        # the main alerts sorted set, remove all alerts_by sorted sets
        # for the contact

        # remove all associated notification rules
        self.notification_rules.each do |nr|
          self.delete_notification_rule(nr)
        end

        @redis.del("contact:#{self.id}", "contact_media:#{self.id}",
                   "contact_media_intervals:#{self.id}",
                   "contact_media_rollup_thresholds:#{self.id}",
                   "contact_tz:#{self.id}", "contact_pagerduty:#{self.id}")
      end

      def pagerduty_credentials
        return unless service_key = @redis.hget("contact_media:#{self.id}", 'pagerduty')
        @redis.hgetall("contact_pagerduty:#{self.id}").
          merge('service_key' => service_key)
      end

      def set_pagerduty_credentials(details)
        @redis.hset("contact_media:#{self.id}", 'pagerduty', details['service_key'])
        @redis.hmset("contact_pagerduty:#{self.id}",
                     *['subdomain', 'token', 'username', 'password'].collect {|f| [f, details[f]]})
      end

      def delete_pagerduty_credentials
        @redis.hdel("contact_media:#{self.id}", 'pagerduty')
        @redis.del("contact_pagerduty:#{self.id}")
      end

      # returns false if this contact was already in the set for the entity
      def add_entity(entity)
        key = "contacts_for:#{entity.id}"
        @redis.sadd(key, self.id)
      end

      # returns false if this contact wasn't in the set for the entity
      def remove_entity(entity)
        key = "contacts_for:#{entity.id}"
        @redis.srem(key, self.id)
      end

      # NB ideally contacts_for:* keys would scope the entity and check by an
      # input source, for namespacing purposes
      def entities(options = {})
        @redis.keys('contacts_for:*').inject({}) {|ret, k|
          if @redis.sismember(k, self.id)
            if k =~ /^contacts_for:([a-zA-Z0-9][a-zA-Z0-9\.\-]*[a-zA-Z0-9])(?::(\w+))?$/
              entity_id = $1
              check = $2

              entity = nil

              if ret.has_key?(entity_id)
                entity = ret[entity_id][:entity]
              else
                entity = Flapjack::Data::Entity.find_by_id(entity_id, :redis => @redis)
                ret[entity_id] = {
                  :entity => entity
                }
                # using a set to ensure unique check values
                ret[entity_id][:checks] = Set.new if options[:checks]
                ret[entity_id][:tags] = entity.tags if entity && options[:tags]
              end

              if options[:checks]
                # if not registered for the check, then was registered for
                # the entity, so add all checks
                ret[entity_id][:checks] |= (check || (entity ? entity.check_list : []))
              end
            end
          end
          ret
        }.values
      end

      def self.entity_ids_for(contact_ids, options = {})
        raise "Redis connection not set" unless redis = options[:redis]

        entity_ids = {}

        temp_set = SecureRandom.uuid
        redis.sadd(temp_set, contact_ids)

        redis.keys('contacts_for:*').each do |k|
          contact_ids = redis.sinter(k, temp_set)
          next if contact_ids.empty?
          next unless k =~ /^contacts_for:([a-zA-Z0-9][a-zA-Z0-9\.\-]*[a-zA-Z0-9])(?::(\w+))?$/

          entity_id = $1
          # check     = $2

          contact_ids.each do |contact_id|
            entity_ids[contact_id] ||= []
            entity_ids[contact_id] << entity_id
          end
        end

        redis.del(temp_set)

        entity_ids
      end

      def name
        [(self.first_name || ''), (self.last_name || '')].join(" ").strip
      end

      def notification_rule_ids
        @redis.smembers("contact_notification_rules:#{self.id}")
      end

      # return an array of the notification rules of this contact
      def notification_rules(opts = {})
        rules = self.notification_rule_ids.inject([]) do |ret, rule_id|
          unless (rule_id.nil? || rule_id == '')
            ret << Flapjack::Data::NotificationRule.find_by_id(rule_id, :redis => @redis)
          end
          ret
        end
        if rules.all? {|r| r.is_specific? } # also true if empty
          rule = self.add_notification_rule({
              :entities           => [],
              :regex_entities     => [],
              :tags               => Set.new([]),
              :regex_tags         => Set.new([]),
              :time_restrictions  => [],
              :warning_media      => ALL_MEDIA,
              :critical_media     => ALL_MEDIA,
              :warning_blackhole  => false,
              :critical_blackhole => false,
            }, :logger => opts[:logger])
          rules.unshift(rule)
        end
        rules
      end

      def add_notification_rule(rule_data, opts = {})
        if logger = opts[:logger]
          logger.debug("add_notification_rule: contact_id: #{self.id} (#{self.id.class})")
        end
        Flapjack::Data::NotificationRule.add(rule_data.merge(:contact_id => self.id),
          :redis => @redis, :logger => opts[:logger])
      end

      # move an existing notification rule from another contact to this one
      def grab_notification_rule(rule)
        @redis.srem("contact_notification_rules:#{rule.contact.id}", rule.id)
        rule.contact_id = self.id
        rule.update({})
        @redis.sadd("contact_notification_rules:#{self.id}", rule.id)
      end

      def delete_notification_rule(rule)
        @redis.srem("contact_notification_rules:#{self.id}", rule.id)
        @redis.del("notification_rule:#{rule.id}")
      end

      # how often to notify this contact on the given media
      # return 15 mins if no value is set
      def interval_for_media(media)
        interval = @redis.hget("contact_media_intervals:#{self.id}", media)
        (interval.nil? || (interval.to_i <= 0)) ? (15 * 60) : interval.to_i
      end

      def set_interval_for_media(media, interval)
        return if 'pagerduty'.eql?(media)
        if interval.nil?
          @redis.hdel("contact_media_intervals:#{self.id}", media)
          return
        end
        @redis.hset("contact_media_intervals:#{self.id}", media, interval)
        self.media_intervals = @redis.hgetall("contact_media_intervals:#{self.id}")
      end

      def rollup_threshold_for_media(media)
        threshold = @redis.hget("contact_media_rollup_thresholds:#{self.id}", media)
        (threshold.nil? || (threshold.to_i <= 0 )) ? nil : threshold.to_i
      end

      def set_rollup_threshold_for_media(media, threshold)
        return if 'pagerduty'.eql?(media)
        if threshold.nil?
          @redis.hdel("contact_media_rollup_thresholds:#{self.id}", media)
          return
        end
        @redis.hset("contact_media_rollup_thresholds:#{self.id}", media, threshold)
        self.media_rollup_thresholds = @redis.hgetall("contact_media_rollup_thresholds:#{self.id}")
      end

      def set_address_for_media(media, address)
        return if 'pagerduty'.eql?(media)
        @redis.hset("contact_media:#{self.id}", media, address)
        self.media = @redis.hgetall("contact_media:#{@id}")
      end

      def remove_media(media)
        @redis.hdel("contact_media:#{self.id}", media)
        @redis.hdel("contact_media_intervals:#{self.id}", media)
        @redis.hdel("contact_media_rollup_thresholds:#{self.id}", media)
        if media == 'pagerduty'
          @redis.del("contact_pagerduty:#{self.id}")
        end
      end

      # drop notifications for
      def drop_notifications?(opts = {})
        media    = opts[:media]
        check    = opts[:check]
        state    = opts[:state]

        # build it and they will come
        @redis.exists("drop_alerts_for_contact:#{self.id}") ||
          (media && @redis.exists("drop_alerts_for_contact:#{self.id}:#{media}")) ||
          (media && check &&
            @redis.exists("drop_alerts_for_contact:#{self.id}:#{media}:#{check}")) ||
          (media && check && state &&
            @redis.exists("drop_alerts_for_contact:#{self.id}:#{media}:#{check}:#{state}"))
      end

      def update_sent_alert_keys(opts = {})
        media  = opts[:media]
        check  = opts[:check]
        state  = opts[:state]
        delete = !! opts[:delete]
        key = "drop_alerts_for_contact:#{self.id}:#{media}:#{check}:#{state}"
        if delete
          @redis.del(key)
        else
          @redis.set(key, 'd')
          @redis.expire(key, self.interval_for_media(media))
          # TODO: #182 - update the alert history keys
        end
      end

      def drop_rollup_notifications_for_media?(media)
        @redis.exists("drop_rollup_alerts_for_contact:#{self.id}:#{media}")
      end

      def update_sent_rollup_alert_keys_for_media(media, opts = {})
        delete = !! opts[:delete]
        key = "drop_rollup_alerts_for_contact:#{self.id}:#{media}"
        if delete
          @redis.del(key)
        else
          @redis.set(key, 'd')
          @redis.expire(key, self.interval_for_media(media))
        end
      end

      def add_alerting_check_for_media(media, event_id)
        @redis.zadd("contact_alerting_checks:#{self.id}:media:#{media}", Time.now.to_i, event_id)
      end

      def remove_alerting_check_for_media(media, event_id)
        @redis.zrem("contact_alerting_checks:#{self.id}:media:#{media}", event_id)
      end

      # removes any checks that are in ok, scheduled or unscheduled maintenance,
      # or are disabled from the alerting checks set for the given media;
      # returns whether this cleaning moved the medium from rollup to recovery
      def clean_alerting_checks_for_media(media)
        cleaned = 0

        alerting_checks  = alerting_checks_for_media(media)
        rollup_threshold = rollup_threshold_for_media(media)

        alerting_checks.each do |check|
          entity_check = Flapjack::Data::EntityCheck.for_event_id(check, :redis => @redis)
          next unless Flapjack::Data::EntityCheck.state_for_event_id?(check, :redis => @redis) == 'ok' ||
            Flapjack::Data::EntityCheck.in_unscheduled_maintenance_for_event_id?(check, :redis => @redis) ||
            Flapjack::Data::EntityCheck.in_scheduled_maintenance_for_event_id?(check, :redis => @redis) ||
            !entity_check.enabled? ||
            !entity_check.contacts.map {|c| c.id}.include?(self.id)

          # FIXME: why can't i get this logging when called from notifier (notification.rb)?
          @logger.debug("removing from alerting checks for #{self.id}/#{media}: #{check}") if @logger
          remove_alerting_check_for_media(media, check)
          cleaned += 1
        end

        return false if rollup_threshold.nil? || (rollup_threshold <= 0) ||
          (alerting_checks.size < rollup_threshold)

        return(cleaned > (alerting_checks.size - rollup_threshold))
      end

      def alerting_checks_for_media(media)
        @redis.zrange("contact_alerting_checks:#{self.id}:media:#{media}", 0, -1)
      end

      def count_alerting_checks_for_media(media)
        @redis.zcard("contact_alerting_checks:#{self.id}:media:#{media}")
      end

      # return a list of media enabled for this contact
      # eg [ 'email', 'sms' ]
      def media_list
        @redis.hkeys("contact_media:#{self.id}") - ['pagerduty']
      end

      def media_ids
        self.media_list.collect {|medium| "#{self.id}_#{medium}" }
      end

      def timezone
        @redis.get("contact_tz:#{self.id}")
      end

      def timezone=(tz_string)
        if tz_string.nil?
          @redis.del("contact_tz:#{self.id}")
        elsif tz_string.is_a?(String) && !ActiveSupport::TimeZone[tz_string].nil?
          @redis.set("contact_tz:#{self.id}", tz_string)
        end
      end

      def time_zone
        return nil if self.timezone.nil?
        ActiveSupport::TimeZone[self.timezone]
      end

      def to_jsonapi(opts = {})
        json_data = {
          "id"                    => self.id,
          "first_name"            => self.first_name,
          "last_name"             => self.last_name,
          "email"                 => self.email,
          "timezone"              => self.timezone,
          "links"                 => {
            :entities               => opts[:entity_ids]          || [],
            :media                  => self.media_ids             || [],
            :notification_rules     => self.notification_rule_ids || [],
          }
        }
        Flapjack.dump_json(json_data)
      end

    private

      def initialize(options = {})
        raise "Redis connection not set" unless @redis = options[:redis]
        @id     = options[:id]
        @logger = options[:logger]
      end

      # NB: should probably be called in the context of a Redis multi block; not doing so
      # here as calling classes may well be adding/updating multiple records in the one
      # operation
      def self.add_or_update(contact_id, contact_data, options = {})
        raise "Redis connection not set" unless redis = options[:redis]

        attrs = (['first_name', 'last_name', 'email'] & contact_data.keys).collect do |key|
          [key, contact_data[key]]
        end.flatten(1)

        redis.hmset("contact:#{contact_id}", *attrs) unless attrs.empty?

        unless contact_data['media'].nil?
          redis.del("contact_media:#{contact_id}")
          redis.del("contact_media_intervals:#{contact_id}")
          redis.del("contact_media_rollup_thresholds:#{contact_id}")
          redis.del("contact_pagerduty:#{contact_id}")

          contact_data['media'].each_pair {|medium, details|
            case medium
            when 'pagerduty'
              redis.hset("contact_media:#{contact_id}", medium, details['service_key'])
              redis.hmset("contact_pagerduty:#{contact_id}",
                          *['subdomain', 'token', 'username', 'password'].collect {|f| [f, details[f]]})
            else
              redis.hset("contact_media:#{contact_id}", medium, details['address'])
              redis.hset("contact_media_intervals:#{contact_id}", medium, details['interval']) if details['interval']
              redis.hset("contact_media_rollup_thresholds:#{contact_id}", medium, details['rollup_threshold']) if details['rollup_threshold']
            end
          }
        end
        if contact_data.key?('timezone')
          tz = contact_data['timezone']
          if tz.nil?
            redis.del("contact_tz:#{contact_id}")
          elsif tz.is_a?(String) && !ActiveSupport::TimeZone[tz].nil?
            redis.set("contact_tz:#{contact_id}", tz )
          end
        end
      end

    end

  end

end
