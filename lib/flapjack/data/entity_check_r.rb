#!/usr/bin/env ruby

require 'oj'

require 'flapjack/patches'

require 'flapjack/data/redis_record'
require 'flapjack/data/check_notification_r'
require 'flapjack/data/check_state_r'
require 'flapjack/data/contact_r'
require 'flapjack/data/scheduled_maintenance_r'
require 'flapjack/data/unscheduled_maintenance_r'
require 'flapjack/data/event'

module Flapjack

  module Data

    class EntityCheckR

      include Flapjack::Data::RedisRecord

      define_attributes :name        => :string,
                        :entity_name => :string,
                        :state       => :string,
                        :summary     => :string,
                        :details     => :string,
                        :enabled     => :boolean,

                        # last_update should just be 'states.last', but the last
                        # change may be an earlier state
                        :last_change_id => :id,

                        # pointing to most recent ones, nil if not in that state
                        :current_unscheduled_maintenance_id => :id,
                        :current_scheduled_maintenance_id   => :id

      index_by :entity_name, :name, :enabled, :state

      has_many :contacts, :class => Flapjack::Data::ContactR

      has_sorted_set :notifications, :class => Flapjack::Data::CheckNotificationR

      has_sorted_set :states, :class => Flapjack::Data::CheckStateR
      has_sorted_set :scheduled_maintenances, :class => Flapjack::Data::ScheduledMaintenanceR
      has_sorted_set :unscheduled_maintenances, :class => Flapjack::Data::UnscheduledMaintenanceR

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

      def self.find_for_event_id(event_id)
        entity_name, check_name = event_id.split(':', 2)
        ids = Flapjack.redis.sinter(self.entity_name_index(entity_name).key,
                                    self.name_index(check_name).key)
        return if ids.empty?
        self.find_by_id(ids.first)
      end

      def self.find_for_entity_name(entity_name, check_name)
        ids = Flapjack.redis.sinter(self.entity_name_index(entity_name).key,
                                    self.name_index(check_name).key)
        return if ids.empty?
        self.find_by_id(ids.first)
      end

      # TODO replace any usages of this with find_by_entity, and load the entity before the call
      def self.find_for_entity_id(entity_id, check_name)
        return unless entity = Flapjack::Data::EntityR.find_by_id(entity_id)
        ids = Flapjack.redis.sinter(self.entity_name_index(entity.name).key,
                                    self.name_index(check_name).key)
        return if ids.empty?
        self.find_by_id(ids.first)
      end

      # TODO method on the has_many proxy, such that:
      #   entity.checks.where(:name => name)
      # will work

      def self.find_for_entity(entity, check_name)
        ids = Flapjack.redis.sinter(self.entity_name_index(entity.name).key,
                                    self.name_index(check_name).key)
        return if ids.empty?
        self.find_by_id(ids.first)
      end

      def self.all_enabled_for_entity(entity)
        self.all_abled_for_entity(true)
      end

      def self.all_disabled_for_entity
        self.all_abled_for_entity(false)
      end

      # OLD self.find_all_for_entity_name(name)
      # NEW: entity = Entity.find_by(:name, name); entity.checks

      # OLD: self.find_all
      # NEW: EntityCheckR.all

      # OLD: self.find_all_by_entity
      # NEW: EntityCheckR.hash_by_entity( EntityCheckR.all )

      # OLD: self.count_all
      # NEW: EntityCheckR.count

      def self.find_all_failing
        keys = Flapjack::Data::CheckStateR.failing_states.collect {|state|
          self.state_index(state.to_s).key
        }
        ids = Flapjack.redis.sunion(*keys).collect {|id| load(id) }
      end

      # OLD self.find_all_failing_unacknowledged
      # NEW self.find_all_failing.reject {|ec| ec.in_unscheduled_maintenance? }

      def self.hash_by_entity(entity_check_list)
        entity_check_list.inject({}) {|memo, ec|
          memo[ec.entity_name] = [] unless memo.has_key?(ec.entity_name)
          memo[ec.entity_name] << ec
          memo
        }
      end

      # OLD self.find_all_failing_by_entity
      # new self.hash_by_entity( self.find_all_failing )

      # OLD: self.count_all_failing
      # NEW: self.find_all_failing.size

      # OLD def in_unscheduled_maintenance?
      # NEW def !current_unscheduled_maintenance_id.nil?

      # OLD def in_scheduled_maintenance?
      # NEW def !current_scheduled_maintenance_id.nil?

      # OLD: current_maintenance(:scheduled => 'scheduled')
      # NEW return unless in_scheduled_maintenance?; self.scheduled_maintenances.last

      # OLD: current_maintenance(:scheduled => 'unscheduled')
      # NEW: return unless in_unscheduled_maintenance?; self.unscheduled_maintenances.last

      # Hmm, this is a bit side-effect-ish
  #     def event_count_at(timestamp)
  #       eca = Flapjack.redis.get("#{@key}:#{timestamp}:count")
  #       return unless (eca && eca =~ /^\d+$/)
  #       eca.to_i
  #     end

      def failed?
        Flapjack::Data::CheckStateR.failing_states.include?( self.state )
      end

      def ok?
        Flapjack::Data::CheckStateR.ok_states.include?( self.state )
      end

      # OLD def contacts
      # NEW (check.contacts + check.entity.contacts).uniq
      # TODO should clear entity remove from checks? probably not...

  #     def tags
  #       entity, check = @key.split(":", 2)
  #       ta = Flapjack::Data::TagSet.new([])
  #       ta += entity.split('.', 2).map {|x| x.downcase}
  #       ta += check.split(' ').map {|x| x.downcase}
  #     end

      private

      def self.all_abled_for_entity(entity)
        Flapjack.redis.sinter(self.entity_name_index(entity.name).key,
                              self.enabled_index(enabled).key).map do |id|
          self.load(id)
        end
      end

    end

  end

end
