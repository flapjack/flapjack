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
                        :enabled     => :boolean

      index_by :entity_name, :name, :enabled, :state

      has_many :contacts, :class_name => 'Flapjack::Data::ContactR'

      # last_update should just be 'states.last', but the last
      # change may be an earlier state
      has_one :last_change, :class_name => 'Flapjack::Data::CheckStateR'

      has_sorted_set :notifications, :class_name => 'Flapjack::Data::CheckNotificationR'

      has_sorted_set :states, :class_name => 'Flapjack::Data::CheckStateR', :key => :timestamp

      # keep two indices for each, so that we can query on the intersection of those
      # indices
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

      # TODO EntityCheck after_save, if !enabled and entity has no enabled checks, disable entity
      #      EntityCheck after_save, if enabled or entity has any enabled checks, enable entity

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

      # OLD: current_maintenance(:scheduled => 'unscheduled')
      # NEW: return unless in_unscheduled_maintenance?; TODO

      # OLD event_count_at(timestamp)
      # NEW TODO retrieve state via its timestamp; state.count

      def failed?
        Flapjack::Data::CheckStateR.failing_states.include?( self.state )
      end

      def ok?
        Flapjack::Data::CheckStateR.ok_states.include?( self.state )
      end

      # TODO maybe (some of) this could be in a before_save callback?
      def update_state(new_state, options = {})
        return unless (Flapjack::Data::CheckStateR.ok_states +
                       Flapjack::Data::CheckStateR.failing_states).include?(new_state)

        opt_timestamp = options[:timestamp] || Time.now.to_i
        opt_summary   = options[:summary]
        opt_details   = options[:details]
        opt_count     = options[:count]

        check_state = nil

        if self.state != new_state
          self.state = new_state
          self.last_change = opt_timestamp

          # FIXME: Iterate through a list of tags associated with an entity:check pair, and update counters

          check_state = Flapjack::Data::CheckStateR.new(:state => new_state,
            :timestamp => opt_timestamp)

          check_state.summary = opt_summary if opt_summary
          check_state.details = opt_details if opt_details
          check_state.count   = opt_count if opt_count
        end

        # Track when we last saw an event for a particular entity:check pair
        entity = self.entity
        entity.enabled = true
        self.enabled = true

        # Even if this isn't a state change, we need to update the current state
        # summary and details (as they may have changed)
        self.summary = (opt_summary || '')
        self.details = (opt_details || '')

        entity.save
        unless check_state.nil?
          check_state.save
          self.states << check_state
        end
        self.save
      end

  #     def create_scheduled_maintenance(start_time, duration, opts = {})
  #       # scheduled maintenance periods have changed, revalidate
  #       update_scheduled_maintenance(:revalidate => true)
  #     end

  #     # if not in scheduled maintenance, looks in scheduled maintenance list for a check to see if
  #     # current state should be set to scheduled maintenance, and sets it as appropriate
        def update_scheduled_maintenance(opts = {})
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

  #     def create_unscheduled_maintenance(start_time, duration, opts = {})
  #       raise ArgumentError, 'start time must be provided as a Unix timestamp' unless start_time && start_time.is_a?(Integer)
  #       raise ArgumentError, 'duration in seconds must be provided' unless duration && duration.is_a?(Integer) && (duration > 0)

  #       summary    = opts[:summary]
  #       time_remaining = (start_time + duration) - Time.now.to_i
  #       if time_remaining > 0
  #         end_unscheduled_maintenance(start_time) if in_unscheduled_maintenance?
  #         Flapjack.redis.setex("#{@key}:unscheduled_maintenance", time_remaining, start_time)
  #       end
  #       Flapjack.redis.zadd("#{@key}:unscheduled_maintenances", duration, start_time)
  #       Flapjack.redis.set("#{@key}:#{start_time}:unscheduled_maintenance:summary", summary)

  #       Flapjack.redis.zadd("#{@key}:sorted_unscheduled_maintenance_timestamps", start_time, start_time)
  #     end

  #     # ends any unscheduled maintenance
  #     def end_unscheduled_maintenance(end_time)
  #       raise ArgumentError, 'end time must be provided as a Unix timestamp' unless end_time && end_time.is_a?(Integer)

  #       if (um_start = Flapjack.redis.get("#{@key}:unscheduled_maintenance"))
  #         duration = end_time - um_start.to_i
  #         @logger.debug("ending unscheduled downtime for #{@key} at #{Time.at(end_time).to_s}") if @logger
  #         Flapjack.redis.del("#{@key}:unscheduled_maintenance")
  #         Flapjack.redis.zadd("#{@key}:unscheduled_maintenances", duration, um_start) # updates existing UM 'score'
  #       else
  #         @logger.debug("end_unscheduled_maintenance called for #{@key} but none found") if @logger
  #       end
  #     end

      # OLD def contacts
      # NEW (check.contacts + check.entity.contacts).uniq
      # TODO should clear entity remove from checks? probably not...

  #     def tags
  #       entity, check = @key.split(":", 2)
  #       ta = Flapjack::Data::TagSet.new([])
  #       ta += entity.split('.', 2).map {|x| x.downcase}
  #       ta += check.split(' ').map {|x| x.downcase}
  #     end

    end

  end

end
