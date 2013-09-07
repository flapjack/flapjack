#!/usr/bin/env ruby

# NB: use of redis.keys probably indicates we should maintain a data
# structure to avoid the need for this type of query

require 'set'
require 'ice_cube'

require 'flapjack/data/redis_record'
require 'flapjack/data/entity'
require 'flapjack/data/notification_rule_r'
require 'flapjack/data/tag'
require 'flapjack/data/tag_set'

module Flapjack

  module Data

    class ContactR

      include Flapjack::Data::RedisRecord

      define_attribute_methods [:first_name, :last_name, :email, :timezone]

      # TODO map contacts_for as 'entity:ID:contact_ids'
      
      has_many :media # , :dependent => :destroy

      has_many :notification_rules, :class => Flapjack::Data::NotificationRuleR

      # TODO a better way to wrap this around the has_many association
      def notification_rules_checked
        rules = self.notification_rules
        if rules.all.all? {|r| r.is_specific? } # also true if empty
          rule = Flapjack::Data::NotificationRuleR.new(
            :entities           => [].to_json,
            :tags               => [].to_json,
            :time_restrictions  => [].to_json,
            :warning_media      => ['email', 'sms', 'jabber', 'pagerduty'].to_json,
            :critical_media     => ['email', 'sms', 'jabber', 'pagerduty'].to_json,
            :warning_blackhole  => false,
            :critical_blackhole => false
          )
          rules << rule
        end
        rules
      end

      # has_many :tags

      # hash_key :pagerduty_credentials

  #     attr_accessor :id, :first_name, :last_name, :email, :media, :media_intervals, :pagerduty_credentials

  #     TAG_PREFIX = 'contact_tag'

      # TODO sort usages of 'Contact.all' by [c.last_name, c.first_name] in the code,
      # or change the association to a sorted_set and provide the sort condition up front
      # (use id if not provided)


      # contact.media_list should be replaced by
      # contact.media.collect {|m| m['address'] }


  #     # ensure that instance variables match redis state
  #     # TODO may want to make this protected/private, it's only
  #     # used in this class
  #     def refresh
  #       self.first_name, self.last_name, self.email =
  #         Flapjack.redis.hmget("contact:#{@id}", 'first_name', 'last_name', 'email')
  #       self.media = Flapjack.redis.hgetall("contact_media:#{@id}")
  #       self.media_intervals = Flapjack.redis.hgetall("contact_media_intervals:#{self.id}")

  #       # similar to code in instance method pagerduty_credentials
  #       if service_key = Flapjack.redis.hget("contact_media:#{@id}", 'pagerduty')
  #         self.pagerduty_credentials =
  #           Flapjack.redis.hgetall("contact_pagerduty:#{@id}").merge('service_key' => service_key)
  #       end
  #     end

  #     def delete!
  #       # remove entity & check registrations -- ugh, this will be slow.
  #       # rather than check if the key is present we'll just request its
  #       # deletion anyway, fewer round-trips
  #       Flapjack.redis.keys('contacts_for:*').each do |cfk|
  #         Flapjack.redis.srem(cfk, self.id)
  #       end

  #       Flapjack.redis.del("drop_alerts_for_contact:#{self.id}")
  #       dafc = Flapjack.redis.keys("drop_alerts_for_contact:#{self.id}:*")
  #       Flapjack.redis.del(*dafc) unless dafc.empty?

  #       # TODO if implemented, alerts_by_contact & alerts_by_check:
  #       # list all alerts from all matched keys, remove them from
  #       # the main alerts sorted set, remove all alerts_by sorted sets
  #       # for the contact

  #       # remove this contact from all tags it's marked with
  #       self.delete_tags(*self.tags.to_a)

  #       # remove all associated notification rules
  #       self.notification_rules.each do |nr|
  #         self.delete_notification_rule(nr)
  #       end

  #       Flapjack.redis.del("contact:#{self.id}", "contact_media:#{self.id}",
  #                  "contact_media_intervals:#{self.id}",
  #                  "contact_tz:#{self.id}", "contact_pagerduty:#{self.id}")
  #     end

  #     def pagerduty_credentials
  #       return unless service_key = Flapjack.redis.hget("contact_media:#{self.id}", 'pagerduty')
  #       Flapjack.redis.hgetall("contact_pagerduty:#{self.id}").
  #         merge('service_key' => service_key)
  #     end

  #     # NB ideally contacts_for:* keys would scope the entity and check by an
  #     # input source, for namespacing purposes
  #     def entities(options = {})
  #       Flapjack.redis.keys('contacts_for:*').inject({}) {|ret, k|
  #         if Flapjack.redis.sismember(k, self.id)
  #           if k =~ /^contacts_for:([a-zA-Z0-9][a-zA-Z0-9\.\-]*[a-zA-Z0-9])(?::(\w+))?$/
  #             entity_id = $1
  #             check = $2

  #             entity = nil

  #             if ret.has_key?(entity_id)
  #               entity = ret[entity_id][:entity]
  #             else
  #               entity = Flapjack::Data::Entity.find_by_id(entity_id)
  #               ret[entity_id] = {
  #                 :entity => entity
  #               }
  #               # using a set to ensure unique check values
  #               ret[entity_id][:checks] = Set.new if options[:checks]
  #               ret[entity_id][:tags] = entity.tags if entity && options[:tags]
  #             end

  #             if options[:checks]
  #               # if not registered for the check, then was registered for
  #               # the entity, so add all checks
  #               ret[entity_id][:checks] |= (check || (entity ? entity.check_list : []))
  #             end
  #           end
  #         end
  #         ret
  #       }.values
  #     end

      # TODO neater way to detect errors?
      def name
        return if invalid? && !(self.errors.keys & [:first_name, :last_name]).empty?
        [(self.first_name || ''), (self.last_name || '')].join(" ").strip
      end

      def destroy
        # # remove entity linkages
        # Flapjack::Data::Entity.each do |entity|
        #   entity.contacts.delete(self)
        # end
        super
      end


  #     def add_notification_rule(rule_data, opts = {})
  #       if logger = opts[:logger]
  #         logger.debug("add_notification_rule: contact_id: #{self.id} (#{self.id.class})")
  #       end
  #       Flapjack::Data::NotificationRule.add(rule_data.merge(:contact_id => self.id),
  #         :logger => opts[:logger])
  #     end

  #     def delete_notification_rule(rule)
  #       Flapjack.redis.srem("contact_notification_rules:#{self.id}", rule.id)
  #       Flapjack.redis.del("notification_rule:#{rule.id}")
  #     end


  #     # drop notifications for
  #     def drop_notifications?(opts = {})
  #       media    = opts[:media]
  #       check    = opts[:check]
  #       state    = opts[:state]

  #       # build it and they will come
  #       Flapjack.redis.exists("drop_alerts_for_contact:#{self.id}") ||
  #         (media && Flapjack.redis.exists("drop_alerts_for_contact:#{self.id}:#{media}")) ||
  #         (media && check &&
  #           Flapjack.redis.exists("drop_alerts_for_contact:#{self.id}:#{media}:#{check}")) ||
  #         (media && check && state &&
  #           Flapjack.redis.exists("drop_alerts_for_contact:#{self.id}:#{media}:#{check}:#{state}"))
  #     end

  #     def update_sent_alert_keys(opts = {})
  #       media  = opts[:media]
  #       check  = opts[:check]
  #       state  = opts[:state]
  #       delete = !! opts[:delete]
  #       key = "drop_alerts_for_contact:#{self.id}:#{media}:#{check}:#{state}"
  #       if delete
  #         Flapjack.redis.del(key)
  #       else
  #         Flapjack.redis.set(key, 'd')
  #         Flapjack.redis.expire(key, self.interval_for_media(media))
  #       end
  #     end

  #     # FIXME
  #     # do a mixin with the following tag methods, they will be the same
  #     # across all objects we allow tags on

  #     # return the set of tags for this contact
  #     def tags
  #       @tags ||= Flapjack::Data::TagSet.new( Flapjack.redis.keys("#{TAG_PREFIX}:*").inject([]) {|memo, tag|
  #         if Flapjack::Data::Tag.find(tag).include?(@id.to_s)
  #           memo << tag.sub(/^#{TAG_PREFIX}:/, '')
  #         end
  #         memo
  #       } )
  #     end

  #     # adds tags to this contact
  #     def add_tags(*enum)
  #       enum.each do |t|
  #         Flapjack::Data::Tag.create("#{TAG_PREFIX}:#{t}", [@id])
  #         tags.add(t)
  #       end
  #     end

  #     # removes tags from this contact
  #     def delete_tags(*enum)
  #       enum.each do |t|
  #         tag = Flapjack::Data::Tag.find("#{TAG_PREFIX}:#{t}")
  #         tag.delete(@id)
  #         tags.delete(t)
  #       end
  #     end

      # return the timezone of the contact, or the system default if none is set
      # TODO cache?
      def time_zone
        tz_string = self.timezone
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

      # sets or removes the time zone for the contact
      # nil should delete TODO test
      def time_zone=(tz)
        self.timezone = tz.respond_to?(:name) ? tz.name : tz
      end

  #     def to_json(*args)
  #       { "id"         => self.id,
  #         "first_name" => self.first_name,
  #         "last_name"  => self.last_name,
  #         "email"      => self.email,
  #         "tags"       => self.tags.to_a }.to_json
  #     end

  #   private

  #     # NB: should probably be called in the context of a Redis multi block; not doing so
  #     # here as calling classes may well be adding/updating multiple records in the one
  #     # operation
  #     def self.add_or_update(contact_id, contact_data, options = {})
  #       # TODO check that the rest of this is safe for the update case
  #       Flapjack.redis.hmset("contact:#{contact_id}",
  #                   *['first_name', 'last_name', 'email'].collect {|f| [f, contact_data[f]]})

  #       unless contact_data['media'].nil?
  #         Flapjack.redis.del("contact_media:#{contact_id}")
  #         Flapjack.redis.del("contact_media_intervals:#{contact_id}")
  #         Flapjack.redis.del("contact_pagerduty:#{contact_id}")

  #         contact_data['media'].each_pair {|medium, details|
  #           case medium
  #           when 'pagerduty'
  #             Flapjack.redis.hset("contact_media:#{contact_id}", medium, details['service_key'])
  #             Flapjack.redis.hmset("contact_pagerduty:#{contact_id}",
  #                         *['subdomain', 'username', 'password'].collect {|f| [f, details[f]]})
  #           else
  #             Flapjack.redis.hset("contact_media:#{contact_id}", medium, details['address'])
  #             Flapjack.redis.hset("contact_media_intervals:#{contact_id}", medium, details['interval']) if details['interval']
  #           end
  #         }
  #       end
  #     end

    end
  end
end
