#!/usr/bin/env ruby

require 'flapjack/data/redis_record'
require 'flapjack/data/check_notification_r'
require 'flapjack/data/check_state_r'
require 'flapjack/data/contact_r'
require 'flapjack/data/scheduled_maintenance_r'
require 'flapjack/data/unscheduled_maintenance_r'

module Flapjack

  module Data

    class EntityCheckR

      include Flapjack::Data::RedisRecord

      define_attributes :name        => :string,
                        :entity_name => :string,
                        :state       => :string,
                        :summary     => :string,
                        :details     => :string,
                        :last_update => :timestamp,
                        :enabled     => :boolean

      index_by :entity_name, :name, :enabled, :state

      has_many :contacts, :class_name => 'Flapjack::Data::ContactR'

      has_one :last_change, :class_name => 'Flapjack::Data::CheckStateR'

      has_sorted_set :notifications, :class_name => 'Flapjack::Data::CheckNotificationR', :key => :timestamp
      has_sorted_set :states, :class_name => 'Flapjack::Data::CheckStateR', :key => :timestamp

      # keep two indices for each, so that we can query on their intersection
      has_sorted_set :scheduled_maintenances_by_start, :class_name => 'Flapjack::Data::ScheduledMaintenanceR',
        :key => :start_time
      has_sorted_set :scheduled_maintenances_by_end, :class_name => 'Flapjack::Data::ScheduledMaintenanceR',
        :key => :end_time

      has_sorted_set :unscheduled_maintenances_by_start, :class_name => 'Flapjack::Data::UnscheduledMaintenanceR',
        :key => :start_time
      has_sorted_set :unscheduled_maintenances_by_end, :class_name => 'Flapjack::Data::UnscheduledMaintenanceR',
        :key => :end_time

      validates :name, :presence => true
      validates :entity_name, :presence => true
      validates :state, :presence => true,
        :inclusion => {:in => Flapjack::Data::CheckStateR.failing_states +
                              Flapjack::Data::CheckStateR.ok_states }

      around_create :handle_state_change_and_enabled
      around_update :handle_state_change_and_enabled

      attr_accessor :count

      def entity
        @entity ||= Flapjack::Data::EntityR.find_by(:name, self.entity_name).first
      end

      # TODO work out when it's valid to create the record if not found

      # OLD def self.find_for_event_id(event_id)
      # NEW entity_name, check_name = event_id.split(':', 2);
      #     EntityCheckR.filter(:entity_name => entity_name, :name => check_name).first

      # OLD def self.find_for_entity_name(entity_name, check_name)
      # NEW EntityCheckR.filter(:entity_name => entity_name, :name => check_name).first

      # OLD def self.find_for_entity_id(entity_id, check_name)
      # NEW entity = EntityR.find_by_id(entity_id)
      #     EntityCheckR.filter(:entity_name => entity.name, :name => check_name).first

      # OLD def self.find_for_entity(entity, check_name)
      # NEW EntityCheckR.filter(:entity_name => entity.name, :name => check_name).first

      # OLD self.find_all_for_entity_name(name)
      # NEW: entity = Entity.find_by(:name, name); entity.checks

      # OLD: self.find_all
      # NEW: EntityCheckR.all

      # OLD: self.find_all_by_entity
      # NEW: EntityCheckR.hash_by_entity_name( EntityCheckR.all )

      # OLD: self.count_all
      # NEW: EntityCheckR.count

      # OLD: self.find_all_failing
      # NEW: self.union(:state => Flapjack::Data::CheckStateR.failing_states.collect).all

      # OLD self.find_all_failing_unacknowledged
      # NEW self.union(:state => Flapjack::Data::CheckStateR.failing_states.collect).
      #        all.reject {|ec| ec.in_unscheduled_maintenance? }

      def self.hash_by_entity_name(entity_check_list)
        entity_check_list.inject({}) {|memo, ec|
          memo[ec.entity_name] = [] unless memo.has_key?(ec.entity_name)
          memo[ec.entity_name] << ec
          memo
        }
      end

      # OLD self.find_all_failing_by_entity
      # new self.hash_by_entity( self.union(:state => Flapjack::Data::CheckStateR.failing_states.collect).all )

      # OLD: self.count_all_failing
      # NEW: self.union(:state => Flapjack::Data::CheckStateR.failing_states.collect).count

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

      def failed?
        Flapjack::Data::CheckStateR.failing_states.include?( self.state )
      end

      def ok?
        Flapjack::Data::CheckStateR.ok_states.include?( self.state )
      end

      # # calling code:
      # ec.last_update = time
      # ec.state = st
      # ec.summary = summary
      # ec.details = details
      # ec.count = count
      # ec.save
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

        check_state = Flapjack::Data::CheckStateR.new(:state => self.state,
          :timestamp => self.last_update,
          :summary => self.summary,
          :details => self.details,
          :count => self.count)
        check_state.save
        self.states << check_state
        self.last_change = check_state

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
          Flapjack::Data::ScheduledMaintenanceR.find_by_id(id)
        }
        return if current_sched_ms.empty?
        # if multiple scheduled maintenances found, find the end_time furthest in the future
        current_sched_ms.max {|sm| sm.end_time }
      end

      def set_unscheduled_maintenance(unsched_maint)
        time_remaining = unsched_maint.end_time - Time.now.to_i

        if time_remaining > 0
          self.clear_unscheduled_maintenance(unsched_maint.start_time)
          Flapjack.redis.setex(unscheduled_maintenance_key, time_remaining, unsched_maint.start_time)
        end

        self.unscheduled_maintenances_by_start << unsched_maint
        self.unscheduled_maintenances_by_end << unsched_maint
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
         # should have this effect on the relevant index -- TODO test
         # Flapjack.redis.zadd("#{@key}:unscheduled_maintenances", duration, um_start) # updates existing UM 'score'
      end

      # TODO check why this skips problem
      def last_notifications_of_each_type
        Flapjack::Data::CheckNotificationR::NOTIFICATION_STATES.inject({}) do |memo, state|
          unless state == :problem
            memo[state] = self.notifications.intersect(:state => state.to_s).last
          end
          memo
        end
      end

      def max_notified_severity_of_current_failure
        notif_timestamp = proc {|notif_state|
          last_notif = self.notifications.intersect(:state => notif_state).last
          last_notif ? last_notif.timestamp : nil
        }

        last_recovery = notif_timestamp('recovery') || 0

        ret = nil

        # relying on 1.9+ ordered hash
        {'critical' => Flapjack::Data::CheckStateR::STATE_CRITICAL,
         'warning'  => Flapjack::Data::CheckStateR::STATE_WARNING,
         'unknown'  => Flapjack::Data::CheckStateR::STATE_UNKNOWN}.each_pair do |state_name, state_result|

          if (last_ts = notif_timestamp('state_name')) && (last_ts > last_recovery)
            ret = state_result
            break
          end
        end

        ret
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
