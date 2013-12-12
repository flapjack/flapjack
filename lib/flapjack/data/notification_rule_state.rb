#!/usr/bin/env ruby

require 'sandstorm/record'

require 'flapjack/data/check_state'

module Flapjack
  module Data
    class NotificationRuleState

      include Sandstorm::Record

      define_attributes :state     => :string,
                        :blackhole => :boolean

      index_by :state, :blackhole

      belongs_to :notification_rule, :class_name => 'Flapjack::Data::Notification',
        :inverse_of => :states

      has_and_belongs_to_many :media, :class_name => 'Flapjack::Data::Medium',
        :inverse_of => :notification_rule_states

      validate :state, :presence => true,
        :inclusion => { :in => Flapjack::Data::CheckState.failing_states }
    end
  end
end