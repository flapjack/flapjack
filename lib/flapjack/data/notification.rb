#!/usr/bin/env ruby

# 'Notification' refers to the template object created when an event occurs,
# from which individual 'Message' objects are created, one for each
# contact+media recipient.

require 'zermelo/records/redis'

module Flapjack
  module Data
    class Notification

      include Zermelo::Records::RedisSet
      include Flapjack::Data::Extensions::ShortName

      define_attributes :severity           => :string,
                        :duration           => :integer,
                        :condition_duration => :float,
                        :event_hash         => :string

      belongs_to :check, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :notifications

      has_one :state, :class_name => 'Flapjack::Data::State',
        :inverse_of => :notification, :after_clear => :destroy_state

      def self.destroy_state(notification_id, st_id)
        # won't be deleted if still referenced elsewhere -- see the State
        # before_destroy callback
        Flapjack::Data::State.intersect(:id => st_id).destroy_all
      end

      validates :severity,
        :inclusion => {:in => Flapjack::Data::Condition.unhealthy.keys +
                              Flapjack::Data::Condition.healthy.keys }

    end
  end
end
