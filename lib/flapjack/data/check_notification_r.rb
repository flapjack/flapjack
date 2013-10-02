#!/usr/bin/env ruby

module Flapjack
  module Data
    class CheckNotificationR

      include Flapjack::Data::RedisRecord

      NOTIFICATION_STATES = [:problem, :warning, :critical, :unknown,
                             :recovery, :acknowledgement]

      define_attributes :state => :string,
                        :summary => :string,
                        :timestamp => :timestamp

      belongs_to :entity_check, :class_name => 'Flapjack::Data::EntityCheckR'

      # OLD def last_notification_for_state(state)
      # NEW entity_check.notifications.intersect(:state => state).last

      # # results aren't really guaranteed if there are multiple notifications
      # # of different types sent at the same time
      # OLD def last_notification
      # NEW entity_check.notifications.last

    end
  end
end