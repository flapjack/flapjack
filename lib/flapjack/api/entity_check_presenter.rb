#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/entity_check'

module Flapjack

  class API < Sinatra::Base

    class EntityCheckPresenter

      def initialize(entity_check)
        @entity_check = entity_check
      end

      def downtimes(start_time, end_time)
        # states is an array of hashes, with [state, timestamp, summary] keys
        states = @entity_check.historical_states(start_time, end_time)
        return states if states.empty?

        # if it started failed, prepend the earlier event
        initial = @entity_check.historical_state_before(states.first[:timestamp])
        states.unshift(initial) if initial && state_failed?(initial[:state])

        # if it ended failed, append the event when it recovered
        if state_failed?(states.last[:state])
          # TODO ensure this event is a recovery, find the first recovery after if not
          last = @entity_check.historical_state_after(states.last)
          states.push(last)
        end

        last_state = nil

        paired_states = states.inject([]) do |ret, obj|

          if state_failed?(obj[:state]) && (last_state.nil? || state_ok?(last_state))
            last_state = obj[:state]
            ret << [obj, nil]
          elsif state_ok?(obj[:state]) && state_failed?(last_state)
            last_state = obj[:state]
            ret.last[1] = obj
          end

          ret
        end
      end

      def unscheduled_outages(start_time, end_time)

        # unsched_outages is an array of hashes, with [duration, timestamp, summary] keys
        unsched_outages = @entity_check.historical_maintenances(start_time, end_time,
          :scheduled => false)

        # to see if we start in an unscheduled maintenance period, we must check all unscheduled
        # maintenances before the period and their durations
        start_in_unsched = @entity_check.historical_maintenances(nil, start_time,
          :scheduled => false).select {|pu|

          (pu[:timestamp] + pu[:duration]) >= start_time
        }

        start_in_unsched + unsched_outages
      end

      def scheduled_outages(start_time, end_time)

        # sched_outages is an array of hashes, with [duration, timestamp, summary] keys
        sched_outages = @entity_check.historical_maintenances(start_time, end_time,
          :scheduled => true)

        # to see if we start in a scheduled maintenance period, we must check all scheduled
        # maintenances before the period and their durations
        start_in_sched = @entity_check.historical_maintenances(nil, start_time,
          :scheduled => true).select {|ps|

          (ps[:timestamp] + ps[:duration]) >= start_time
        }

        start_in_sched + sched_outages
      end

      def unscheduled_downtime(start_time, end_time)

        sched_outages = scheduled_outages

        down = downtimes

        # TODO

      end

      private

        def state_ok?(state)
          state == Flapjack::Data::EntityCheck::STATE_OK
        end

        def state_failed?(state)
          [Flapjack::Data::EntityCheck::STATE_WARNING,
           Flapjack::Data::EntityCheck::STATE_CRITICAL].include?(state)
        end

    end

  end

end