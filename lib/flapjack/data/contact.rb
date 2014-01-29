#!/usr/bin/env ruby

# NB: use of redis.keys probably indicates we should maintain a data
# structure to avoid the need for this type of query

require 'set'
require 'ice_cube'

require 'sandstorm/record'

require 'flapjack/data/check_state'
require 'flapjack/data/entity'
require 'flapjack/data/medium'
require 'flapjack/data/notification_block'
require 'flapjack/data/notification_rule'
require 'flapjack/data/notification_rule_state'

require 'securerandom'

module Flapjack

  module Data

    class Contact

      attr_accessor :linked_entity_ids

      include Sandstorm::Record
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false

      define_attributes :first_name            => :string,
                        :last_name             => :string,
                        :email                 => :string,
                        :timezone              => :string,
                        :pagerduty_credentials => :hash,
                        :tags                  => :set

      has_and_belongs_to_many :entities, :class_name => 'Flapjack::Data::Entity',
        :inverse_of => :contacts

      has_many :media, :class_name => 'Flapjack::Data::Medium'
      has_many :notification_rules, :class_name => 'Flapjack::Data::NotificationRule'

      before_destroy :remove_child_records
      def remove_child_records
        self.media.each               {|medium|             medium.destroy }
        self.notification_rules.each  {|notification_rule|  notification_rule.destroy }
      end

      # wrap the has_many to create the generic rule if none exists
      alias_method :orig_notification_rules, :notification_rules
      def notification_rules
        rules = orig_notification_rules
        contact_media = media.all

        if rules.all.all? {|r| r.is_specific? } # also true if empty
          nr_fail_states = Flapjack::Data::CheckState.failing_states.collect do |fail_state|
            state = Flapjack::Data::NotificationRuleState.new(:state => fail_state,
              :blackhole => false)
            state.save
            state.media.add(*contact_media) unless 'unknown'.eql?(fail_state) || contact_media.empty?
            state
          end

          rule = Flapjack::Data::NotificationRule.new(
            :entities           => Set.new,
            :tags               => Set.new,
            :time_restrictions  => []
          )
          rule.save
          rule.states.add(*nr_fail_states)
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

      def self.entities_jsonapi(contact_ids, options = {})
        entity_data = {}
        linked_entity_ids = {}

        contact_ids.each do |contact_id|
          contact = Flapjack::Data::Contact.find_by_id(contact_id)
          next if contact.nil?

          entity_ids = contact.entities.ids

          entity_ids.each do |entity_id|
            next if entity_data.has_key?(entity_id)
            entity = Flapjack::Data::Entity.find_by_id(entity_id)
            entity_data[entity_id] = {:id => entity_id, :name => entity.name}
          end
          linked_entity_ids[contact_id] = entity_ids
        end

        [entity_data.values, linked_entity_ids]
      end

      # TODO usage of to_json should have :only => [:first_name, :last_name, :email, :tags]
      # TODO linked_entity_ids handling

    end
  end
end
