#!/usr/bin/env ruby

require 'sandstorm/records/redis_record'

require 'flapjack/data/check_state'

module Flapjack
  module Data
    class NotificationRuleState

      include Sandstorm::Records::RedisRecord

      define_attributes :state     => :string

      index_by :state

      belongs_to :notification_rule, :class_name => 'Flapjack::Data::Notification',
        :inverse_of => :states

      has_and_belongs_to_many :media, :class_name => 'Flapjack::Data::Medium',
        :inverse_of => :notification_rule_states

      validate :state, :presence => true,
        :inclusion => { :in => Flapjack::Data::CheckState.failing_states }

      # TODO validate that notification_rule and media belong to the same contact

    end
  end
end