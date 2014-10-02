#!/usr/bin/env ruby

require 'sandstorm/records/redis_record'

module Flapjack
  module Data
    class NotificationRuleDrop

      include Sandstorm::Records::RedisRecord

      define_attributes :state     => :string

      index_by :state

      belongs_to :notification_rule, :class_name => 'Flapjack::Data::Notification',
        :inverse_of => :states

      validate :state, :presence => true,
        :inclusion => { :in => Flapjack::Data::CheckState.failing_states }

    end
  end
end