#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/entity_check'

module Flapjack

  class API < Sinatra::Base

    class EntityCheckPresenter

      def initialize(entity_check)
        @entity_check = entity_check
      end

      def outages(start_time, end_time)
        # states is an array of hashes, with [state, timestamp, summary] keys
        states = @entity_check.historical_states(start_time, end_time)
        return states if states.empty?

        # if it started failed, prepend the earlier event
        initial = @entity_check.historical_state_before(states.first[:timestamp])
        states.unshift(initial) if (initial &&
          (initial[:state] == Flapjack::Data::EntityCheck::STATE_CRITICAL))

        # if it ended failed, append the event when it recovered
        if states.last[:state] == Flapjack::Data::EntityCheck::STATE_CRITICAL
          # TODO ensure this event is not CRITICAL, get first non-CRITICAL if so
          last = @entity_check.historical_state_after(states.last)
          states.push(last)
        end

        last_state = nil

        # returns an array of hashes, with [:start_time, :end_time, :summary]
        states.inject([]) do |ret, obj|
          if (obj[:state] == Flapjack::Data::EntityCheck::STATE_CRITICAL) &&
            (last_state.nil? || (last_state != Flapjack::Data::EntityCheck::STATE_CRITICAL))

            last_state = obj[:state]
            ret << {:start_time => obj[:timestamp], :end_time => nil, :summary => obj[:summary]}
          elsif (obj[:state] != Flapjack::Data::EntityCheck::STATE_CRITICAL) &&
            (last_state == Flapjack::Data::EntityCheck::STATE_CRITICAL)

            last_state = obj[:state]
            ret.last[:end_time] = obj[:timestamp]
          end
          ret
        end
      end

      def unscheduled_maintenance(start_time, end_time)

        # unsched_maintenance is an array of hashes, with [duration, timestamp, summary] keys
        unsched_maintenance = @entity_check.historical_maintenances(start_time, end_time,
          :scheduled => false)

        # to see if we start in an unscheduled maintenance period, we must check all unscheduled
        # maintenances before the period and their durations
        start_in_unsched = @entity_check.historical_maintenances(nil, start_time,
          :scheduled => false).select {|pu|

          (pu[:timestamp] + pu[:duration]) >= start_time
        }

        start_in_unsched + unsched_maintenance
      end

      def scheduled_maintenance(start_time, end_time)

        # sched_maintenance is an array of hashes, with [duration, timestamp, summary] keys
        sched_maintenance = @entity_check.historical_maintenances(start_time, end_time,
          :scheduled => true)

        # to see if we start in a scheduled maintenance period, we must check all scheduled
        # maintenances before the period and their durations
        start_in_sched = @entity_check.historical_maintenances(nil, start_time,
          :scheduled => true).select {|ps|

          (ps[:timestamp] + ps[:duration]) >= start_time
        }

        start_in_sched + sched_maintenance
      end

      def downtime(start_time, end_time)
        sched_maintenance = scheduled_maintenance

        down = outages

        total_secs = 0
        percentage = 0

        down.each do |d|

          start  = d[0]
          finish = d[1]

          # TODO determine overlap against all sched_maintenance periods

        end

        {:total_seconds => total_secs, :percentage => percentage}
      end

    end

  end

end