#!/usr/bin/env ruby

module Flapjack
  module Data
    class CheckNotificationR

      include Flapjack::Data::RedisRecord

      NOTIFICATION_STATES = [:problem, :warning, :critical, :unknown,
                             :recovery, :acknowledgement]


  # 'problem', 'warning', 'critical', 'recovery', 'acknowledgement'

  #     def last_notification_for_state(state)
  #       return unless NOTIFICATION_STATES.include?(state)
  #       ln = Flapjack.redis.get("#{@key}:last_#{state.to_s}_notification")
  #       return {:timestamp => nil, :summary => nil} unless (ln && ln =~ /^\d+$/)
  #       { :timestamp => ln.to_i,
  #         :summary => Flapjack.redis.get("#{@key}:#{ln.to_i}:summary") }
  #     end

  #     def last_notifications_of_each_type
  #       NOTIFICATION_STATES.inject({}) do |memo, state|
  #         memo[state] = last_notification_for_state(state) unless (state == :problem)
  #         memo
  #       end
  #     end

  #     def max_notified_severity_of_current_failure
  #       last_recovery = last_notification_for_state(:recovery)[:timestamp] || 0

  #       last_critical = last_notification_for_state(:critical)[:timestamp]
  #       return STATE_CRITICAL if last_critical && (last_critical > last_recovery)

  #       last_warning = last_notification_for_state(:warning)[:timestamp]
  #       return STATE_WARNING if last_warning && (last_warning > last_recovery)

  #       last_unknown = last_notification_for_state(:unknown)[:timestamp]
  #       return STATE_UNKNOWN if last_unknown && (last_unknown > last_recovery)

  #       nil
  #     end

  #     # unpredictable results if there are multiple notifications of different
  #     # types sent at the same time
  #     def last_notification
  #       nils = { :type => nil, :timestamp => nil, :summary => nil }

  #       lne = last_notifications_of_each_type
  #       ln = lne.delete_if {|type, notif| notif[:timestamp].nil? || notif[:timestamp].to_i <= 0 }
  #       if ln.find {|type, notif| type == :warning or type == :critical}
  #         ln = ln.delete_if {|type, notif| type == :problem }
  #       end
  #       return nils if ln.empty?
  #       lns = ln.sort_by { |type, notif| notif[:timestamp] }.last
  #       { :type => lns[0], :timestamp => lns[1][:timestamp], :summary => lns[1][:summary] }
  #     end


    end
  end
end