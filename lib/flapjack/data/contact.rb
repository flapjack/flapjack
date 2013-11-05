#!/usr/bin/env ruby

# NB: use of redis.keys probably indicates we should maintain a data
# structure to avoid the need for this type of query

require 'set'
require 'ice_cube'

require 'sandstorm/record'

require 'flapjack/data/entity'
require 'flapjack/data/medium'
require 'flapjack/data/notification_block'
require 'flapjack/data/notification_rule'

module Flapjack

  module Data

    class Contact

      include Sandstorm::Record

      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false

      define_attributes :first_name            => :string,
                        :last_name             => :string,
                        :email                 => :string,
                        :timezone              => :string,
                        :pagerduty_credentials => :hash,
                        :tags                  => :set

      has_many :entities, :class_name => 'Flapjack::Data::Entity'
      has_many :media, :class_name => 'Flapjack::Data::Medium'
      has_many :notification_rules, :class_name => 'Flapjack::Data::NotificationRule'

      before_destroy :remove_child_records
      def remove_child_records
        self.media.each               {|medium|             medium.destroy }
        self.notification_rules.each  {|notification_rule|  notification_rule.destroy }
      end

      after_destroy :remove_entity_linkages
      def remove_entity_linkages
        entities.each do |entity|
          entity.contacts.delete(self)
        end
      end

      # wrap the has_many to create the generic rule if none exists
      alias_method :orig_notification_rules, :notification_rules
      def notification_rules
        rules = orig_notification_rules
        if rules.all.all? {|r| r.is_specific? } # also true if empty
          rule = Flapjack::Data::NotificationRule.create_generic
          rules << rule
        end
        rules
      end

      # TODO sort usages of 'Contact.all' by [c.last_name, c.first_name] in the code

      def name
        return if invalid? && !(self.errors.keys & [:first_name, :last_name]).empty?
        [(self.first_name || ''), (self.last_name || '')].join(" ").strip
      end

      # return the timezone of the contact, or the system default if none is set
      # TODO cache?
      def time_zone(opts = {})
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
