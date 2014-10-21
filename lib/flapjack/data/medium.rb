#!/usr/bin/env ruby

require 'sandstorm/records/redis_record'
require 'flapjack/data/alert'
require 'flapjack/data/check'

module Flapjack

  module Data

    class Medium

      include Sandstorm::Records::RedisRecord
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false

      TYPES = ['email', 'sms', 'jabber', 'pagerduty', 'sns', 'sms_twilio']

      define_attributes :type              => :string,
                        :address           => :string,
                        :interval          => :integer,
                        :rollup_threshold  => :integer,
                        :last_notification => :timestamp

      belongs_to :contact, :class_name => 'Flapjack::Data::Contact', :inverse_of => :media

      has_and_belongs_to_many :routes,
        :class_name => 'Flapjack::Data::Route', :inverse_of => :media

      has_many :alerts, :class_name => 'Flapjack::Data::Alert'

      index_by :type

      validates :type, :presence => true,
        :inclusion => {:in => Flapjack::Data::Medium::TYPES }
      validates :address, :presence => true
      validates :interval, :presence => true,
        :numericality => {:greater_than => 0, :only_integer => true}

      before_destroy :remove_child_records
      def remove_child_records
        # self.notification_blocks.each {|notification_block| notification_block.destroy }
      end


      def alert(notification, opts = {})
        logger = opts[:logger]

        alert = Flapjack::Data::Alert.new(:state => opts[:state],
          :state_duration => notification.state_duration,
          :acknowledgement_duration => notification.duration,
          :notification_type => notification.type)

        unless medium.rollup_threshold.nil?

          # alerting_check_ids = medium.alerting_check_ids

          # if alerting_checks_ids.size >= medium.rollup_threshold
          #   alert.rollup_type = 'problem'
          # elsif 'problem'.eql?(medium.last_rollup_type)
          #   alert.rollup_type = 'recovery'
          # end

          # # also medium could store that last message sent was 'normal', 'rollup'
          # # or 'recovery' ? what happens if rule is deleted, or tags change, or something?
        end

        unless alert.save
          raise "Couldn't save alert: #{alert.errors.full_messages.inspect}"
        end

        alert
      end

      def alerting_check_ids(options = {})
        default_timezone = opts[:default_timezone]
        # timestamp = options[:timestamp] || Time.now

        route_ids = self.routes.ids
        return [] if route_ids.empty?

        timezone = self.contact.time_zone(:default => default_timezone)
        # TODO is_occuring_now should be is_occurring_at, take a timestamp
        active_routes = self.routes.select {|route| route.is_occurring_now?(timezone) }

        active_routes_by_id = active_routes.inject({}) do |memo, ar|
          memo[ar.id] = ar
          memo
        end

        rule_ids_by_route_id = Flapjack::Data::Route.associated_ids_for_rule(*active_route_ids)

        # invert the above, grouping route ids by rule id
        routes_by_rule_id = rule_ids_by_route_id.inject({}) do |memo, (ro_id, ru_id)|
          memo[ru_id] ||= []
          memo[ru_id] << active_routes_by_id[ro_id]
          memo
        end

        rule_ids = routes_by_rule_id.keys

        tag_ids_by_rule_id = Flapjack::Data::Rule.associated_ids_for_tags(*rule_ids)

        tag_ids = Set.new(tag_ids_by_rule_id.values).flatten

        check_ids_by_tag_id = Flapjack::Data::Tag.associated_ids_for_checks(*tag_ids)

        # TODO reject checks in scheduled/unscheduled maintenance

        rule_ids.inject([]) do |memo, ru_id|

          routes_for_rule = routes_by_rule_id[ru_id]

          # if any route has empty state then all problem states are valid
          states = if routes_for_rule.any? {|r| r.state.nil? || r.state.empty? }
            Flapjack::Data::CheckState.failing_states
          else
            routes_for_rule.collect(&:state)
          end

          opts = {:state => states}

          tag_ids_for_rule = tag_ids_by_rule_id[ru_id]

          # if the rule has no tags then all checks are valid
          unless tag_ids_for_rule.empty?
            # intersection of checks for all tags for the rule
            rule_check_ids = tag_ids_for_rule.collect {|t_id| check_ids_by_tag_id}.inject(&:'&') }
            opts.update(:id => rule_check_ids)
          end

          memo += Flapjack::Data::Check.intersect(opts).ids
          memo
        end
      end

      # def drop_notifications?(opts = {})
      #   check = opts[:check]

      #   attrs = if opts[:rollup]
      #     {:rollup => true}
      #   else
      #     {:state  => opts[:state]}
      #   end

      #   # drop any expired blocks for this medium
      #   self.notification_blocks.
      #     intersect_range(nil, Time.now.to_i, :by_score => true).
      #     intersect(attrs).destroy_all

      #   if opts[:rollup]
      #     self.notification_blocks.intersect(attrs).count > 0
      #   else
      #     block_ids = self.notification_blocks.intersect(attrs).ids
      #     return false if block_ids.empty?
      #     (block_ids & check.notification_blocks.ids).size > 0
      #   end
      # end

      # def update_sent_alert_keys(opts = {})
      #   rollup  = opts[:rollup]
      #   delete  = !!opts[:delete]
      #   check   = opts[:check]
      #   state   = opts[:state]

      #   attrs = {}
      #   check_block_ids = nil

      #   if rollup
      #     attrs.update(:rollup => true)
      #   else
      #     check_block_ids = check.notification_blocks.ids
      #     attrs.update(:state => state)
      #   end

      #   if delete
      #     block_ids = self.notification_blocks.intersect(attrs).ids

      #     block_ids.each do |block_id|
      #       next if !check_block_ids.nil? && !check_block_ids.include?(block_id)
      #       next unless block = Flapjack::Data::NotificationBlock.find_by_id(block_id)
      #       self.notification_blocks.delete(block)
      #       block.destroy
      #     end
      #   else
      #     expire_at = Time.now + (self.interval * 60)

      #     new_block = false
      #     block = self.notification_blocks.intersect(attrs).all.first

      #     if block.nil?
      #       block = Flapjack::Data::NotificationBlock.new(attrs.merge(:expire_at => expire_at))
      #       block.save
      #     else
      #       # need to remove it from the sorted_set that uses expire_at as a key,
      #       # change and re-add -- see https://github.com/flapjack/sandstorm/issues/1
      #       self.notification_blocks.delete(block)
      #       check.notification_blocks.delete(block) if check
      #       block.expire_at = expire_at
      #       block.save
      #     end
      #     check.notification_blocks << block if check
      #     self.notification_blocks << block
      #   end
      # end

      # def clean_alerting_checks
      #   checks_to_remove = alerting_checks.select do |check|
      #     Flapjack::Data::CheckState.ok_states.include?(check.state) ||
      #     check.in_unscheduled_maintenance? ||
      #     check.in_scheduled_maintenance?
      #   end

      #   return 0 if checks_to_remove.empty?
      #   alerting_checks.delete(*checks_to_remove)
      #   checks_to_remove.size
      # end

      def as_json(opts = {})
        super.as_json(opts.merge(:root => false)).merge(
          :links => {
            :contacts   => opts[:contact_ids] || [],
            :routes     => opts[:route_ids] || []
          }
        )
      end

    end

  end

end