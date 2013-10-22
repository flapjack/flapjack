#!/usr/bin/env ruby

require 'sandstorm/record'

require 'flapjack/data/check_state'
require 'flapjack/data/contact'
require 'flapjack/data/scheduled_maintenance'
require 'flapjack/data/unscheduled_maintenance'

module Flapjack

  module Data

    class Check

      include Sandstorm::Record

      define_attributes :name        => :string,
                        :entity_name => :string,
                        :state       => :string,
                        :summary     => :string,
                        :details     => :string,
                        :last_update => :timestamp,
                        :enabled     => :boolean

      index_by :entity_name, :name, :enabled, :state

      has_many :contacts, :class_name => 'Flapjack::Data::Contact'

      has_sorted_set :states, :class_name => 'Flapjack::Data::CheckState', :key => :timestamp

      # keep two indices for each, so that we can query on their intersection
      has_sorted_set :scheduled_maintenances_by_start, :class_name => 'Flapjack::Data::ScheduledMaintenance',
        :key => :start_time
      has_sorted_set :scheduled_maintenances_by_end, :class_name => 'Flapjack::Data::ScheduledMaintenance',
        :key => :end_time

      has_sorted_set :unscheduled_maintenances_by_start, :class_name => 'Flapjack::Data::UnscheduledMaintenance',
        :key => :start_time
      has_sorted_set :unscheduled_maintenances_by_end, :class_name => 'Flapjack::Data::UnscheduledMaintenance',
        :key => :end_time

      validates :name, :presence => true
      validates :entity_name, :presence => true
      validates :state,
        :inclusion => {:in => Flapjack::Data::CheckState.all_states, :allow_blank => true }

      around_create :handle_state_change_and_enabled
      around_update :handle_state_change_and_enabled

      attr_accessor :count

      def entity
        @entity ||= Flapjack::Data::Entity.intersect(:name => self.entity_name).all.first
      end

      # TODO work out when it's valid to create the record if not found

      # OLD def self.find_for_event_id(event_id)
      # NEW entity_name, check_name = event_id.split(':', 2);
      #     Check.intersect(:entity_name => entity_name, :name => check_name).first

      # OLD def self.find_for_entity_name(entity_name, check_name)
      # NEW Check.intersect(:entity_name => entity_name, :name => check_name).first

      # OLD def self.find_for_entity_id(entity_id, check_name)
      # NEW entity = Entity.find_by_id(entity_id)
      #     Check.intersect(:entity_name => entity.name, :name => check_name).first

      # OLD def self.find_for_entity(entity, check_name)
      # NEW Check.intersect(:entity_name => entity.name, :name => check_name).first

      # OLD self.find_all_for_entity_name(name)
      # NEW: entity = Entity.find_by(:name, name); entity.checks

      # OLD: self.find_all
      # NEW: Check.all

      # OLD: self.find_all_by_entity
      # NEW: Check.hash_by_entity_name( Check.all )

      # OLD: self.count_all
      # NEW: Check.count

      # OLD: self.find_all_failing
      # NEW: self.union(:state => Flapjack::Data::CheckState.failing_states).all

      # OLD self.find_all_failing_unacknowledged
      # NEW self.union(:state => Flapjack::Data::CheckState.failing_states).
      #        all.reject {|ec| ec.in_unscheduled_maintenance? }

      def self.hash_by_entity_name(entity_check_list)
        entity_check_list.inject({}) {|memo, ec|
          memo[ec.entity_name] = [] unless memo.has_key?(ec.entity_name)
          memo[ec.entity_name] << ec
          memo
        }
      end

      # OLD self.find_all_failing_by_entity
      # new self.hash_by_entity( self.union(:state => Flapjack::Data::CheckState.failing_states).all )

      # OLD: self.count_all_failing
      # NEW: self.union(:state => Flapjack::Data::CheckState.failing_states).count

      def in_scheduled_maintenance?
        !!Flapjack.redis.get("#{self.record_key}:expiring:scheduled_maintenance")
      end

      def in_unscheduled_maintenance?
        !!Flapjack.redis.get("#{self.record_key}:expiring:unscheduled_maintenance")
      end

      # OLD event_count_at(timestamp)
      # NEW retrieve state via its timestamp; state.count

      # OLD def contacts
      # NEW (check.contacts + check.entity.contacts).uniq
      # TODO should clear entity remove from checks? probably not...

      def handle_state_change_and_enabled
        if self.changed.include?('last_update')
          self.enabled = true
        end

        yield

        if self.changed.include?('enabled')
          entity = self.entity

          if self.enabled
            entity.enabled = true
            entity.save
          else
            if entity.checks.intersect(:enabled => true).empty?
              entity.enabled = false
              entity.save
            end
          end
        end

        # TODO validation for: if state has changed, last_update must have changed
        return unless self.changed.include?('last_update') && self.changed.include?('state')

        # FIXME: Iterate through a list of tags associated with an entity:check pair, and update counters

        check_state = Flapjack::Data::CheckState.new(:state => self.state,
          :timestamp => self.last_update,
          :summary => self.summary,
          :details => self.details,
          :count => self.count)
        check_state.save
        self.states << check_state

        update_current_scheduled_maintenance
      end


      # OLD def create_scheduled_maintenance
      def add_scheduled_maintenance(sched_maint)
        self.scheduled_maintenances_by_start << sched_maint
        self.scheduled_maintenances_by_end << sched_maint
        update_current_scheduled_maintenance(:revalidate => true)
      end

      # TODO allow summary to be changed as part of the termination
      def end_scheduled_maintenance(sched_maint, time_to_end_at)
        if sched_maint.start_time >= time_to_end_at

          # the scheduled maintenance period is in the future
          self.scheduled_maintenances_by_start.delete(sched_maint)
          self.scheduled_maintenances_by_end.delete(sched_maint)
          sched_maint.destroy

          # scheduled maintenance periods have changed, revalidate
          # TODO don't think this is necessary for the future case
          update_current_scheduled_maintenance(:revalidate => true)
          return true
        elsif sched_maint.end_time >= time_to_end_at
          # it spans the current time, so we'll stop it at that point
          sched_maint.end_time = time_to_end_at
          sched_maint.save

          # scheduled maintenance periods have changed, revalidate
          update_current_scheduled_maintenance(:revalidate => true)
          return true
        end

        false
      end

      def current_scheduled_maintenance
        current_time = Time.now.to_i
        start_prior_ids = self.scheduled_maintenances_by_start.
          intersect_range(nil, current_time, :by_score => true).ids
        end_later_ids = self.scheduled_maintenances_by_end.
          intersect_range(current_time, nil, :by_score => true).ids

        current_sched_ms = (start_prior_ids & end_later_ids).map {|id|
          Flapjack::Data::ScheduledMaintenance.find_by_id(id)
        }
        return if current_sched_ms.empty?
        # if multiple scheduled maintenances found, find the end_time furthest in the future
        current_sched_ms.max {|sm| sm.end_time }
      end

      def set_unscheduled_maintenance(unsched_maint)
        current_time = Time.now.to_i
        time_remaining = unsched_maint.end_time - current_time

        if time_remaining > 0
          self.clear_unscheduled_maintenance(unsched_maint.start_time)
          Flapjack.redis.setex(unscheduled_maintenance_key, time_remaining, unsched_maint.start_time)
        end

        self.unscheduled_maintenances_by_start << unsched_maint
        self.unscheduled_maintenances_by_end << unsched_maint
        self.last_update = current_time.to_i # ack is treated as changing state in this case TODO check
        self.save
      end

      def current_unscheduled_maintenance
        return unless ts = Flapjack.redis.get(unscheduled_maintenance_key)
        self.unscheduled_maintenances_by_start.intersect_range(ts, ts, :by_score => true).first
      end

      # OLD def end_unscheduled_maintenance(end_time)
      def clear_unscheduled_maintenance(end_time)
        return unless um_start = Flapjack.redis.get(unscheduled_maintenance_key)

        @logger.debug("ending unscheduled downtime for #{self.entity_name}:#{self.name} at #{Time.at(end_time).to_s}") if @logger
        Flapjack.redis.del(unscheduled_maintenance_key)

        usm = self.unscheduled_maintenances_by_start.intersect(:start_time => um_start).first

        if usm.nil?
          @logger.error("no unscheduled_maintenance period found with start time #{Time.at(end_time).to_s}") if @logger
          return
        end

         usm.end_time = end_time
         usm.save
      end

      # OLD def last_notification_for_state(type)
      # NEW entity_check.states.intersect(:state => state, :notified => true).last
      # TODO ack needs self.unscheduled_maintenances_by_start.intersect(:notified => true).last

      # # results aren't really guaranteed if there are multiple notifications
      # # of different types sent at the same time
      # OLD def last_notification
      # NEW entity_check.states.intersect(:notified => true).last

      def last_notification
        events = [self.unscheduled_maintenances_by_start.intersect(:notified => true).last,
                  self.states.intersect(:notified => true).last].compact

        notifying_event = case events.size
        when 2
          events.max {|a, b| (a.notified ? a.notification_times.to_a.sort.last.to_i : 0) <=>
                             (b.notified ? b.notification_times.to_a.sort.last.to_i : 0) }
        when 1
          events.first
        else
          nil
        end
      end

      def max_notified_severity_of_current_failure
        last_recovery = self.states.intersect(:notified => true, :state => 'ok').last
        last_recovery_time = last_recovery ? last_recovery.timestamp.to_i : 0

        # puts "max_severity recovery #{last_recovery.inspect} // #{last_recovery_time}"

        states_since_last_recovery =
          self.states.intersect_range(last_recovery_time, nil, :by_score => true).
            collect(&:state).uniq

        ['critical', 'warning', 'unknown'].detect {|st| states_since_last_recovery.include?(st) }
      end

      def tags
        @tags ||= Set.new(self.entity_name.split('.', 2).map(&:downcase) +
                          self.name.split(' ').map(&:downcase))
      end

      private

      def scheduled_maintenance_key
        "#{self.record_key}:expiring:scheduled_maintenance"
      end

      def unscheduled_maintenance_key
        "#{self.record_key}:expiring:unscheduled_maintenance"
      end

      # if not in scheduled maintenance, looks in scheduled maintenance list for a check to see if
      # current state should be set to scheduled maintenance, and sets it as appropriate
      def update_current_scheduled_maintenance(opts = {})
        return if !opts[:revalidate] && self.in_scheduled_maintenance?

        # are we within a scheduled maintenance period?
        current_sched_maint = current_scheduled_maintenance

        if current_sched_maint.nil?
          if opts[:revalidate]
            Flapjack.redis.del("#{self.record_key}:expiring:scheduled_maintenance")
          end
          return
        end

        Flapjack.redis.setex("#{self.record_key}:expiring:scheduled_maintenance",
                             current_sched_maint.end_time.to_i.to_s,
                             current_sched_maint.id)
      end

    end

  end

end
