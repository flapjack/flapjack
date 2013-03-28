#!/usr/bin/env ruby

# NB: use of redis.keys probably indicates we should maintain a data
# structure to avoid the need for this type of query

require 'set'
require 'ice_cube'
require 'flapjack/data/entity'
require 'flapjack/data/notification_rule'
require 'tzinfo'

module Flapjack

  module Data

    class Contact

      attr_accessor :id, :first_name, :last_name, :email, :media, :pagerduty_credentials

      TAG_PREFIX = 'contact_tag'

      def self.all(options = {})
        raise "Redis connection not set" unless redis = options[:redis]

        contact_keys = redis.keys('contact:*')

        contact_keys.inject([]) {|ret, k|
          k =~ /^contact:(\d+)$/
          id = $1
          contact = self.find_by_id(id, :redis => redis)
          ret << contact if contact
          ret
        }.sort_by {|c| [c.last_name, c.first_name]}
      end

      def self.delete_all(options = {})
        raise "Redis connection not set" unless redis = options[:redis]

        keys_to_delete = redis.keys("contact:*") +
                         redis.keys("contact_media:*") +
                         # FIXME: when we do source tagging we can properly
                         # clean up contacts_for: keys
                         # redis.keys('contacts_for:*') +
                         redis.keys("contact_pagerduty:*")

        redis.del(keys_to_delete) unless keys_to_delete.length == 0
      end

      def self.find_by_id(contact_id, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        raise "No id value passed" unless contact_id
        logger = options[:logger]

        return unless redis.hexists("contact:#{contact_id}", 'first_name')

        fn, ln, em = redis.hmget("contact:#{contact_id}", 'first_name', 'last_name', 'email')
        media_addresses = redis.hgetall("contact_media:#{contact_id}")

        # similar to code in instance method pagerduty_credentials
        pc = nil
        if service_key = redis.hget("contact_media:#{contact_id}", 'pagerduty')
          pc = redis.hgetall("contact_pagerduty:#{contact_id}").merge('service_key' => service_key)
        end

        self.new(:first_name            => fn,
                 :last_name             => ln,
                 :email                 => em,
                 :id                    => contact_id,
                 :media                 => media_addresses,
                 :pagerduty_credentials => pc,
                 :redis                 => redis )
      end


      # NB: should probably be called in the context of a Redis multi block; not doing so
      # here as calling classes may well be adding/updating multiple records in the one
      # operation
      # TODO maybe return the instantiated Contact record?
      def self.add(contact, options = {})
        raise "Redis connection not set" unless redis = options[:redis]

        redis.del("contact:#{contact['id']}",
                  "contact_media:#{contact['id']}",
                  "contact_pagerduty:#{contact['id']}")

        redis.hmset("contact:#{contact['id']}",
                    *['first_name', 'last_name', 'email'].collect {|f| [f, contact[f]]})

        unless contact['media'].nil?
          contact['media'].each_pair {|medium, address|
            case medium
            when 'pagerduty'
              redis.hset("contact_media:#{contact['id']}", medium, address['service_key'])
              redis.hmset("contact_pagerduty:#{contact['id']}",
                          *['subdomain', 'username', 'password'].collect {|f| [f, address[f]]})
            else
              redis.hset("contact_media:#{contact['id']}", medium, address)
            end
          }
        end
      end


      def pagerduty_credentials
        return unless service_key = @redis.hget("contact_media:#{self.id}", 'pagerduty')
        @redis.hgetall("contact_pagerduty:#{self.id}").
          merge('service_key' => service_key)
      end

      def entities_and_checks
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
                # using a set to ensure unique check values
                ret[entity_id][:checks] = Set.new
              end

              if check
                # just add this check for the entity
                ret[entity_id][:checks] |= check
              else
                # registered for the entity so add all checks
                ret[entity_id][:checks] |= entity.check_list
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
          Flapjack::Data::NotificationRule.find_by_id(rule_id, {:redis => @redis})
        }.compact
      end

      def media_intervals
        @redis.hgetall("contact_media_intervals:#{self.id}")
      end

      # how often to notify this contact on the given media
      # return 15 mins if no value is set
      def interval_for_media(media)
        @redis.hget("contact_media_intervals:#{self.id}", media) || 15 * 60
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
        media = opts[:media]
        check = opts[:check]
        state = opts[:state]
        key = "drop_alerts_for_contact:#{self.id}:#{media}:#{check}:#{state}"
        @redis.set(key, 'd')
        @redis.expire(key, self.interval_for_media(media))
      end

      # FIXME
      # do a mixin with the following tag methods, they will be the same
      # across all objects we allow tags on

      # return the set of tags for this contact
      def tags
        @tags ||= ::Set.new( @redis.keys("#{TAG_PREFIX}:*").inject([]) {|memo, tag|
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

      # return the timezone string of the contact, or the system default if none is set
      def timezone
        tz_string = @redis.get("contact_tz:#{self.id}")
        tz_string = 'UTC' if (tz_string.nil? || tz_string.empty?)
        begin
          tz = ::TZInfo::Timezone.new(tz_string)
        rescue ::TZInfo::InvalidTimezoneIdentifier
          logger.warn("Invalid timezone string set for contact #{self.id} (#{tz_string})")
          # FIXME: allow setting a default other than UTC in flapjack_config.yml
          tz = ::TZInfo::Timezone.new('UTC')
        end
        tz.identifier
      end

      # sets or removes the timezone string for the contact
      def timezone=(tz_string)
        if tz_string.nil?
          @redis.del("contact_tz:#{self.id}")
        else
          begin
            tz = ::TZInfo::Timezone.new(tz_string)
          rescue ::TZInfo::InvalidTimezoneIdentifier
            logger.warn("Invalid timezone requested to be set for contact #{self.id} (#{tz_string})")
            return false
          end
          @redis.set("contact_tz:#{self.id}", tz.identifier)
        end
      end

      def as_json(opts = {})
        { "id"         => self.id,
          "first_name" => self.first_name,
          "last_name"  => self.last_name,
          "email"      => self.email,
          "tags"       => self.tags.to_a }
      end

    private

      def initialize(options = {})
        raise "Redis connection not set" unless @redis = options[:redis]
        [:first_name, :last_name, :email, :media, :id].each do |field|
          instance_variable_set(:"@#{field.to_s}", options[field])
        end
      end

    end

  end

end
