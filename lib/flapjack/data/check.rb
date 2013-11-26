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

      define_attributes :name               => :string,
                        :entity_name        => :string,
                        :state              => :string,
                        :summary            => :string,
                        :details            => :string,
                        :last_update        => :timestamp,
                        :last_problem_alert => :timestamp,
                        :enabled            => :boolean

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

      has_sorted_set :notification_blocks, :class_name => 'Flapjack::Data::NotificationBlock',
        :key => :expire_at

      has_and_belongs_to_many :alerting_media, :class_name => 'Flapjack::Data::Medium',
        :inverse_of => :alerting_checks

      # the following 3 associations are used internally, for the notification
      # and alert queue inter-pikelet workflow
      has_many :notifications, :class_name => 'Flapjack::Data::Notification'
      has_many :alerts, :class_name => 'Flapjack::Data::Alert'
      has_many :rollup_alerts, :class_name => 'Flapjack::Data::RollupAlert'

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

      def self.hash_by_entity_name(entity_check_list)
        entity_check_list.inject({}) {|memo, ec|
          memo[ec.entity_name] = [] unless memo.has_key?(ec.entity_name)
          memo[ec.entity_name] << ec
          memo
        }
      end

      def in_scheduled_maintenance?
        !scheduled_maintenance_ids_at(Time.now).empty?
      end

      def in_unscheduled_maintenance?
        !unscheduled_maintenance_ids_at(Time.now).empty?
      end

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
      end


      def add_scheduled_maintenance(sched_maint)
        self.scheduled_maintenances_by_start << sched_maint
        self.scheduled_maintenances_by_end << sched_maint
      end

      # TODO allow summary to be changed as part of the termination
      def end_scheduled_maintenance(sched_maint, at_time)
        at_time = Time.at(at_time) unless at_time.is_a?(Time)

        if sched_maint.start_time >= at_time
          # the scheduled maintenance period is in the future
          self.scheduled_maintenances_by_start.delete(sched_maint)
          self.scheduled_maintenances_by_end.delete(sched_maint)
          sched_maint.destroy
          return true
        end

        if sched_maint.end_time >= at_time
          # it spans the current time, so we'll stop it at that point
          # need to remove it from the sorted_set that uses the end_time as a key,
          # change and re-add -- see https://github.com/ali-graham/sandstorm/issues/1
          # TODO should this be in a multi/exec block?
          self.scheduled_maintenances_by_end.delete(sched_maint)
          sched_maint.end_time = at_time
          sched_maint.save
          self.scheduled_maintenances_by_end.add(sched_maint)
          return true
        end

        false
      end

      # def current_scheduled_maintenance
      def scheduled_maintenance_at(at_time)
        current_sched_ms = scheduled_maintenance_ids_at(at_time).map {|id|
          Flapjack::Data::ScheduledMaintenance.find_by_id(id)
        }
        return if current_sched_ms.empty?
        # if multiple scheduled maintenances found, find the end_time furthest in the future
        current_sched_ms.max {|sm| sm.end_time }
      end

      def unscheduled_maintenance_at(at_time)
        current_unsched_ms = unscheduled_maintenance_ids_at(at_time).map {|id|
          Flapjack::Data::UnscheduledMaintenance.find_by_id(id)
        }
        return if current_unsched_ms.empty?
        # if multiple unscheduled maintenances found, find the end_time furthest in the future
        current_unsched_ms.max {|um| um.end_time }
      end

      def set_unscheduled_maintenance(unsched_maint)
        current_time = Time.now

        # time_remaining
        if (unsched_maint.end_time - current_time) > 0
          self.clear_unscheduled_maintenance(unsched_maint.start_time)
        end

        self.unscheduled_maintenances_by_start << unsched_maint
        self.unscheduled_maintenances_by_end << unsched_maint
        self.last_update = current_time.to_i # ack is treated as changing state in this case
        self.save
      end

      def clear_unscheduled_maintenance(end_time)
        return unless unsched_maint = unscheduled_maintenance_at(Time.now)
        # need to remove it from the sorted_set that uses the end_time as a key,
        # change and re-add -- see https://github.com/ali-graham/sandstorm/issues/1
        # TODO should this be in a multi/exec block?
        self.unscheduled_maintenances_by_end.delete(unsched_maint)
        unsched_maint.end_time = end_time
        unsched_maint.save
        self.unscheduled_maintenances_by_end.add(unsched_maint)
      end

      def last_notification
        events = [self.unscheduled_maintenances_by_start.intersect(:notified => true).last,
                  self.states.intersect(:notified => true).last].compact

        case events.size
        when 2
          events.max_by {|e| e.last_notification_count }
        when 1
          events.first
        else
          nil
        end
      end

      def max_notified_severity_of_current_failure
        last_recovery = self.states.intersect(:notified => true, :state => 'ok').last
        last_recovery_time = last_recovery ? last_recovery.timestamp.to_i : 0

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

      def scheduled_maintenance_ids_at(at_time)
        at_time = Time.at(at_time) unless at_time.is_a?(Time)

        start_prior_ids = self.scheduled_maintenances_by_start.
          intersect_range(nil, at_time.to_i, :by_score => true).ids
        end_later_ids = self.scheduled_maintenances_by_end.
          intersect_range(at_time.to_i + 1, nil, :by_score => true).ids

        start_prior_ids & end_later_ids
      end

      def unscheduled_maintenance_ids_at(at_time)
        at_time = Time.at(at_time) unless at_time.is_a?(Time)

        start_prior_ids = self.unscheduled_maintenances_by_start.
          intersect_range(nil, at_time.to_i, :by_score => true).ids
        end_later_ids = self.unscheduled_maintenances_by_end.
          intersect_range(at_time.to_i + 1, nil, :by_score => true).ids

        start_prior_ids & end_later_ids
      end

    end

  end

end
