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

      # TODO check why this skips problem
      def self.last_notifications_of_each_type(entity_check)
        NOTIFICATION_STATES.inject({}) do |memo, state|
          unless state == :problem
            memo[state] = entity_check.notifications.intersect(:state => state.to_s).last
          end
          memo
        end
      end

      def self.max_notified_severity_of_current_failure(entity_check)
        notif_timestamp = proc {|notif_state|
          last_notif = entity_check.notifications.intersect(:state => notif_state).last
          last_notif ? last_notif.timestamp : nil
        }

        last_recovery = notif_timestamp('recovery') || 0

        ret = nil

        # relying on 1.9+ ordered hash
        {'critical' => STATE_CRITICAL,
         'warning'  => STATE_WARNING,
         'unknown'  => STATE_UNKNOWN}.each_pair do |state_name, state_result|

          if (last_ts = notif_timestamp('state_name')) && (last_ts > last_recovery)
            ret = state_result
            break
          end
        end

        ret
      end

      # # results aren't really guaranteed if there are multiple notifications
      # # of different types sent at the same time
      # OLD def last_notification
      # NEW entity_check.notifications.last

    end
  end
end