#!/usr/bin/env ruby

# 'Notification' refers to the template object created when an event occurs,
# from which individual 'Message' objects are created, one for each
# contact+media recipient.

require 'sandstorm/records/redis_record'

require 'flapjack/data/alert'
require 'flapjack/data/contact'

module Flapjack
  module Data
    class Notification

      include Sandstorm::Records::RedisRecord

      attr_accessor :logger

      # NB can't use has_one associations for the states, as the redis persistence
      # is only transitory (used to trigger a queue pop)
      define_attributes :state_duration => :integer,
                        :severity       => :string,
                        :type           => :string,
                        :time           => :timestamp,
                        :duration       => :integer,
                        :event_hash     => :string

      belongs_to :check, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :notifications

      # state association will not be set for notification tests
      belongs_to :state, :class_name => 'Flapjack::Data::CheckState',
        :inverse_of => :current_notifications
      belongs_to :previous_state, :class_name => 'Flapjack::Data::CheckState',
        :inverse_of => :previous_notifications

      validate :state_duration, :presence => true
      validate :severity, :presence => true
      validate :type, :presence => true
      validate :time, :presence => true
      validate :event_hash, :presence => true

      # TODO ensure 'unacknowledged_failures' behaviour is covered

      # query for 'recovery' notification should be for 'ok' state, intersect notified == true
      # query for 'acknowledgement' notification should be 'acknowledgement' state, intersect notified == true
      # any query for 'problem', 'critical', 'warning', 'unknown' notification should be
      # for union of 'critical', 'warning', 'unknown' states, intersect notified == true

      def self.severity_for_state(state, max_notified_severity)
        if ([state, max_notified_severity] & ['critical', 'test_notifications']).any?
          'critical'
        elsif [state, max_notified_severity].include?('warning')
          'warning'
        elsif [state, max_notified_severity].include?('unknown')
          'unknown'
        else
          'ok'
        end
      end

      def state_or_ack
        case self.type
        when 'acknowledgement', 'test'
          self.type
        else
          st = self.state
          st ? st.state : nil
        end
      end

    end
  end
end
