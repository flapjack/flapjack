#!/usr/bin/env ruby

require 'sandstorm/record'

module Flapjack

  module Data

    class Medium

      include Sandstorm::Record

      TYPES = ['email', 'sms', 'jabber', 'pagerduty']

      define_attributes :type             => :string,
                        :address          => :string,
                        :interval         => :integer,
                        :rollup_threshold => :integer

      belongs_to :contact, :class_name => 'Flapjack::Data::Contact', :inverse_of => :media

      has_many :alerts, :class_name => 'Flapjack::Data::Alert'

      has_and_belongs_to_many :alerting_checks,
        :class_name => 'Flapjack::Data::Check', :inverse_of => :alerting_media

      has_sorted_set :notification_blocks,
        :class_name => 'Flapjack::Data::NotificationBlock', :key => :expire_at

      has_and_belongs_to_many :notification_rule_states,
        :class_name => 'Flapjack::Data::NotificationRuleState', :inverse_of => :media

      index_by :type

      validates :type, :presence => true,
        :inclusion => {:in => Flapjack::Data::Medium::TYPES }
      validates :address, :presence => true
      validates :interval, :presence => true,
        :numericality => {:greater_than => 0, :only_integer => true}

      before_destroy :remove_child_records
      def remove_child_records
        self.notification_blocks.each {|notification_block| notification_block.destroy }
      end

      def drop_notifications?(opts = {})
        check = opts[:check]

        attrs = if opts[:rollup]
          {:rollup => true}
        else
          {:state  => opts[:state]}
        end

        # drop any expired blocks for this medium
        self.notification_blocks.
          intersect_range(nil, Time.now.to_i, :by_score => true).
          intersect(attrs).destroy_all

        if opts[:rollup]
          self.notification_blocks.intersect(attrs).count > 0
        else
          block_ids = self.notification_blocks.intersect(attrs).ids
          return false if block_ids.empty?
          (block_ids & check.notification_blocks.ids).size > 0
        end
      end

      def update_sent_alert_keys(opts = {})
        rollup  = opts[:rollup]
        delete  = !!opts[:delete]
        check   = opts[:check]
        state   = opts[:state]

        attrs = {}
        check_block_ids = nil

        if rollup
          attrs.update(:rollup => true)
        else
          check_block_ids = check.notification_blocks.ids
          attrs.update(:state => state)
        end

        if delete
          block_ids = self.notification_blocks.intersect(attrs).ids

          block_ids.each do |block_id|
            next if !check_block_ids.nil? && !check_block_ids.include?(block_id)
            next unless block = Flapjack::Data::NotificationBlock.find_by_id(block_id)
            self.notification_blocks.delete(block)
            block.destroy
          end
        else
          expire_at = Time.now + (self.interval * 60)

          new_block = false
          block = self.notification_blocks.intersect(attrs).all.first

          if block.nil?
            block = Flapjack::Data::NotificationBlock.new(attrs.merge(:expire_at => expire_at))
            block.save
          else
            # need to remove it from the sorted_set that uses expire_at as a key,
            # change and re-add -- see https://github.com/ali-graham/sandstorm/issues/1
            # TODO should this be in a multi/exec block?
            self.notification_blocks.delete(block)
            if check
              check.notification_blocks.delete(block)
            end
            block.expire_at = expire_at
            block.save
          end
          if check
            check.notification_blocks << block
          end
          self.notification_blocks << block
        end
      end

      def clean_alerting_checks
        self.class.send(:lock, Flapjack::Data::Check,
          Flapjack::Data::ScheduledMaintenance,
          Flapjack::Data::UnscheduledMaintenance,
          Flapjack::Data::Entity,
          Flapjack::Data::Contact) do

          checks_to_remove = alerting_checks.select do |check|
            Flapjack::Data::CheckState.ok_states.include?(check.state) ||
            check.in_unscheduled_maintenance? ||
            check.in_scheduled_maintenance? ||
            !check.entity.contacts.ids.include?(self.contact.id)
          end

          if checks_to_remove.empty?
            0
          else
            alerting_checks.delete(*checks_to_remove)
            checks_to_remove.size
          end
        end
      end

      def as_json(opts = {})
        super.as_json(opts).merge(
          :time_restrictions        => @time_restrictions,
          :links => {
            :contact                  => [opts[:contact_id]].compact,
            :notification_rule_states => opts[:notification_rule_states_ids] || []
          }
        )
      end

    end

  end

end