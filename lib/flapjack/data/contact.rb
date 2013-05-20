#!/usr/bin/env ruby

# NB: use of redis.keys probably indicates we should maintain a data
# structure to avoid the need for this type of query

require 'set'
require 'ice_cube'
require 'flapjack/data/entity'
require 'flapjack/data/notification_rule'
require 'flapjack/data/tag'
require 'flapjack/data/tag_set'

module Flapjack

  module Data

    class Contact

      attr_accessor :id, :first_name, :last_name, :email, :media, :pagerduty_credentials

      TAG_PREFIX = 'contact_tag'

      def self.all(options = {})
        raise "Redis connection not set" unless redis = options[:redis]

        redis.keys('contact:*').inject([]) {|ret, k|
          k =~ /^contact:(\d+)$/
          id = $1
          contact = self.find_by_id(id, :redis => redis)
          ret << contact if contact
          ret
        }.sort_by {|c| [c.last_name, c.first_name]}
      end

      def self.find_by_id(contact_id, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        raise "No id value passed" unless contact_id
        logger = options[:logger]

        # sanity check
        return unless redis.hexists("contact:#{contact_id}", 'first_name')

        contact = self.new(:id => contact_id, :redis => redis)
        contact.refresh
        contact
      end

      def self.add(contact_data, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        contact_id = contact_data['id']
        raise "Contact id value not provided" if contact_id.nil?

        if contact = self.find_by_id(contact_id, :redis => redis)
          contact.delete!
        end

        self.add_or_update(contact_id, contact_data, :redis => redis)
        self.find_by_id(contact_id, :redis => redis)
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
        self.first_name, self.last_name, self.email =
          @redis.hmget("contact:#{@id}", 'first_name', 'last_name', 'email')
        self.media = @redis.hgetall("contact_media:#{@id}")

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

        # remove this contact from all tags it's marked with
        self.delete_tags(*self.tags.to_a)

        # remove all associated notification rules
        self.notification_rules.each do |nr|
          self.delete_notification_rule(nr)
        end

        @redis.del("contact:#{self.id}", "contact_media:#{self.id}",
                   "contact_media_intervals:#{self.id}",
                   "contact_tz:#{self.id}", "contact_pagerduty:#{self.id}")
      end

      def pagerduty_credentials
        return unless service_key = @redis.hget("contact_media:#{self.id}", 'pagerduty')
        @redis.hgetall("contact_pagerduty:#{self.id}").
          merge('service_key' => service_key)
      end

      # NB ideally contacts_for:* keys would scope the entity and check by an
      # input source, for namespacing purposes
      def entities(options = {})
        @redis.keys('contacts_for:*').inject({}) {|ret, k|
          if @redis.sismember(k, self.id)
            if k =~ /^contacts_for:([a-zA-Z0-9][a-zA-Z0-9\.\-]*[a-zA-Z0-9])(?::(\w+))?$/
              entity_id = $1
              check = $2

              unless ret.has_key?(entity_id)
                ret[entity_id] = {}
                if entity_name = @redis.hget("entity:#{entity_id}", 'name')
                  entity = Flapjack::Data::Entity.new(:name => entity_name,
                             :id => entity_id, :redis => @redis)
                  ret[entity_id][:entity] = entity
                end
                if options[:checks]
                  # using a set to ensure unique check values
                  ret[entity_id][:checks] = Set.new
                end
              end

              if options[:checks]
                # if not registered for the check, then was registered for
                # the entity, so add all checks
                ret[entity_id][:checks] |= (check || entity.check_list)
              end

              if options[:tags]
                ret[entity_id][:tags] = entity.tags
              end
            end
          end
          ret
        }.values
      end

      def name
        [(self.first_name || ''), (self.last_name || '')].join(" ").strip
      end

      # return an array of the notification rules of this contact
      def notification_rules
        @redis.smembers("contact_notification_rules:#{self.id}").collect { |rule_id|
          next if (rule_id.nil? || rule_id == '')
          Flapjack::Data::NotificationRule.find_by_id(rule_id, {:redis => @redis })
        }.compact
      end

      def add_notification_rule(rule_data)
        Flapjack::Data::NotificationRule.add(rule_data.merge(:contact_id => self.id),
          :redis => @redis)
      end

      def delete_notification_rule(rule)
        @redis.srem("contact_notification_rules:#{self.id}", rule.id)
        @redis.del("notification_rule:#{rule.id}")
      end

      def media_intervals
        @redis.hgetall("contact_media_intervals:#{self.id}")
      end

      # how often to notify this contact on the given media
      # return 15 mins if no value is set
      def interval_for_media(media)
        interval = @redis.hget("contact_media_intervals:#{self.id}", media)
        (interval.nil? || (interval.to_i <= 0)) ? (15 * 60) : interval.to_i
      end

      def set_interval_for_media(media, interval)
        raise "invalid interval" unless interval.is_a?(Integer)
        @redis.hset("contact_media_intervals:#{self.id}", media, interval)
      end

      def set_address_for_media(media, address)
        @redis.hset("contact_media:#{self.id}", media, address)
        if media == 'pagerduty'
          # FIXME - work out what to do when changing the pagerduty service key (address)
          # probably best solution is to remove the need to have the username and password
          # and subdomain as pagerduty's updated api's mean we don't them anymore I think...
        end
      end

      def remove_media(media)
        @redis.hdel("contact_media:#{self.id}", media)
        @redis.hdel("contact_media_intervals:#{self.id}", media)
        if media == 'pagerduty'
          @redis.del("contact_pagerduty:#{self.id}")
        end
      end

      # drop notifications for
      def drop_notifications?(opts)
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

      def update_sent_alert_keys(opts)
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
        end
      end

      # FIXME
      # do a mixin with the following tag methods, they will be the same
      # across all objects we allow tags on

      # return the set of tags for this contact
      def tags
        @tags ||= Flapjack::Data::TagSet.new( @redis.keys("#{TAG_PREFIX}:*").inject([]) {|memo, tag|
          if Flapjack::Data::Tag.find(tag, :redis => @redis).include?(@id.to_s)
            memo << tag.sub(/^#{TAG_PREFIX}:/, '')
          end
          memo
        } )
      end

      # adds tags to this contact
      def add_tags(*enum)
        enum.each do |t|
          Flapjack::Data::Tag.create("#{TAG_PREFIX}:#{t}", [@id], :redis => @redis)
          tags.add(t)
        end
      end

      # removes tags from this contact
      def delete_tags(*enum)
        enum.each do |t|
          tag = Flapjack::Data::Tag.find("#{TAG_PREFIX}:#{t}", :redis => @redis)
          tag.delete(@id)
          tags.delete(t)
        end
      end

      # return a list of media enabled for this contact
      # eg [ 'email', 'sms' ]
      def media_list
        @redis.hkeys("contact_media:#{self.id}")
      end

      # return the timezone of the contact, or the system default if none is set
      # TODO cache?
      def timezone(opts = {})
        logger = opts[:logger]

        tz_string = @redis.get("contact_tz:#{self.id}")
        tz = opts[:default] if (tz_string.nil? || tz_string.empty?)

        if tz.nil?
          begin
            tz = ActiveSupport::TimeZone.new(tz_string)
          rescue ArgumentError
            if logger
              logger.warn("Invalid timezone string set for contact #{self.id} or TZ (#{tz_string}), using 'UTC'!")
            end
            tz = ActiveSupport::TimeZone.new('UTC')
          end
        end
        tz
      end

      # sets or removes the timezone for the contact
      def timezone=(tz)
        if tz.nil?
          @redis.del("contact_tz:#{self.id}")
        else
          # ActiveSupport::TimeZone or String
          @redis.set("contact_tz:#{self.id}",
            tz.respond_to?(:name) ? tz.name : tz )
        end
      end

      def to_json(*args)
        { "id"         => self.id,
          "first_name" => self.first_name,
          "last_name"  => self.last_name,
          "email"      => self.email,
          "tags"       => self.tags.to_a }.to_json
      end

    private

      def initialize(options = {})
        raise "Redis connection not set" unless @redis = options[:redis]
        @id = options[:id]
      end

      # NB: should probably be called in the context of a Redis multi block; not doing so
      # here as calling classes may well be adding/updating multiple records in the one
      # operation
      def self.add_or_update(contact_id, contact_data, options = {})
        raise "Redis connection not set" unless redis = options[:redis]

        # TODO check that the rest of this is safe for the update case
        redis.hmset("contact:#{contact_id}",
                    *['first_name', 'last_name', 'email'].collect {|f| [f, contact_data[f]]})

        unless contact_data['media'].nil?
          redis.del("contact_media:#{contact_id}")
          redis.del("contact_media_intervals:#{contact_id}")
          redis.del("contact_pagerduty:#{contact_id}")

          contact_data['media'].each_pair {|medium, details|
            case medium
            when 'pagerduty'
              redis.hset("contact_media:#{contact_id}", medium, details['service_key'])
              redis.hmset("contact_pagerduty:#{contact_id}",
                          *['subdomain', 'username', 'password'].collect {|f| [f, details[f]]})
            else
              redis.hset("contact_media:#{contact_id}", medium, details['address'])
              redis.hset("contact_media_intervals:#{contact_id}", medium, details['interval']) if details['interval']
            end
          }
        end
      end

    end

  end

end
