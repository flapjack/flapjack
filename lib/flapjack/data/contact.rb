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

      has_sorted_set :notification_blocks, :class_name => 'Flapjack::Data::NotificationBlock',
        :key => :expire_at

      before_destroy :remove_child_records
      def remove_child_records
        self.media.each               {|medium|             medium.destroy }
        self.notification_rules.each  {|notification_rule|  notification_rule.destroy }
        self.notification_blocks.each {|notification_block| notification_block.destroy }
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

      def expire_notification_blocks(time = Time.now)
        self.notification_blocks.intersect_range(nil, time.to_i, :by_score => true).each do |block|
          self.notification_blocks.delete(block)
          block.destroy
        end
      end

      def drop_notifications?(opts = {})
        media_type   = opts[:media]
        entity_check = opts[:entity_check]
        state        = opts[:state]

        # drop any expired blocks
        expire_notification_blocks(Time.now)

        # # NB: not sure if the partial checks are used yet, disabling
        # # this isn't ideal, maybe more sophisticated intersects are the answer?
        # self.notification_blocks.all.any? {|block|
        #   block.media_type.nil? && block.entity_check_id.nil? && block.state.nil?
        # } ||
        # self.notification_blocks.intersect(:media_type => media_type).all.any? {|block|
        #   block.entity_check_id.nil? && block.state.nil?
        # } ||
        # self.notification_blocks.intersect(:media_type => media_type, :entity_check_id => entity_check.id).all.any? {|block|
        #   block.state.nil?
        # } ||
        !self.notification_blocks.intersect(:media_type => media_type,
          :entity_check_id => entity_check.id, :state => state).empty?
      end

      def update_sent_alert_keys(opts = {})
        media_type   = opts[:media]
        entity_check = opts[:entity_check]
        state        = opts[:state]
        delete       = !!opts[:delete]

        attrs = {:media_type => media_type,
          :entity_check_id => entity_check.id, :state => state}

        if delete
          self.notification_blocks.intersect(attrs).all.each do |block|
            self.notification_blocks.delete(block)
            block.destroy
          end
        else
          media = self.media.intersect(:type => media_type).all.first
          unless media.nil?
            expire_at = Time.now + (media.interval * 60)

            new_block = false
            block = Flapjack::Data::NotificationBlock.intersect(attrs).all.first

            if block.nil?
              block = Flapjack::Data::NotificationBlock.new(attrs)
              new_block = true
            end
            block.expire_at = expire_at
            block.save
            if new_block
              self.notification_blocks << block
            end
          end
        end
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
