#!/usr/bin/env ruby

# NB: use of redis.keys probably indicates we should maintain a data
# structure to avoid the need for this type of query

require 'set'
require 'ice_cube'

require 'flapjack/data/redis_record'
# require 'flapjack/data/entity_r'
require 'flapjack/data/medium_r'
require 'flapjack/data/notification_rule_r'

module Flapjack

  module Data

    class ContactR

      include Flapjack::Data::RedisRecord

      define_attributes :first_name            => :string,
                        :last_name             => :string,
                        :email                 => :string,
                        :timezone              => :string,
                        :pagerduty_credentials => :hash,
                        :tags                  => :set

      # TODO map contacts_for as 'entity:ID:contact_ids', entity#has_many :contacts

      has_many :media, :class => Flapjack::Data::MediumR # , :dependent => :destroy

      has_many :notification_rules, :class => Flapjack::Data::NotificationRuleR

      # TODO a better way to wrap this around the has_many association
      def notification_rules_checked
        rules = self.notification_rules
        if rules.all.all? {|r| r.is_specific? } # also true if empty
          rule = Flapjack::Data::NotificationRuleR.create_generic
          rules << rule
        end
        rules
      end

      # TODO sort usages of 'Contact.all' by [c.last_name, c.first_name] in the code,
      # or change the association to a sorted_set and provide the sort condition up front
      # (use id if not provided)

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

      # TODO usage of to_json should have :only => [:first_name, :last_name, :email, :tags]

    end
  end
end
