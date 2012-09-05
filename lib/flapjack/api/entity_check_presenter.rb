#!/usr/bin/env ruby

# Formats entity/check data for presentation by the API methods in Flapjack::API.

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

            # flipped to failed, mark next outage
            last_state = obj[:state]
            ret << {:start_time => obj[:timestamp], :end_time => nil, :summary => obj[:summary]}
          elsif (obj[:state] != Flapjack::Data::EntityCheck::STATE_CRITICAL) &&
            (last_state == Flapjack::Data::EntityCheck::STATE_CRITICAL)

            # flipped to not failed, mark end time for the current outage
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

      # TODO test whether the below overlapping logic is prone to off-by-one
      # errors; the numbers may line up more neatly if we consider outages to
      # start one second after the maintenance period ends.
      #
      # TODO test performance with larger data sets
      def downtime(start_time, end_time)
        sched_maintenances = scheduled_maintenance(start_time, end_time)

        outs = outages(start_time, end_time)

        total_secs = 0
        percentage = 0

        unless outs.empty?

          # Initially we need to check for cases where a scheduled
          # maintenance period is fully covered by an outage period.
          # We then create two new outage peiods to cover the time around
          # the scheduled maintenance period, and remove the original.

          sched_maintenances.each do |sm|

            split_outs = []

            outs.each { |o|
              next unless o[:start_time] < sm[:start_time] &&
                o[:end_time] > sm[:end_time]
              o[:delete] = true
              split_outs += [{:start_time => o[:start_time],
                              :end_time => sm[:start_time],
                              :summary => "#{o[:summary]} [split start]"},
                             {:start_time => sm[:end_time],
                              :end_time => o[:end_time],
                              :summary => "#{o[:summary]} [split finish]"}]
            }

            outs.reject! {|o| o[:delete]}
            outs += split_outs
            # not strictly necessary to keep the data sorted, but
            # will make more sense while debgging
            outs.sort! {|a,b| a[:start_time] <=> b[:start_time]}
          end

          sched_maintenances.each do |sm|

            outs.each do |o|
              # skip if already flagged as fully overlapped when
              # comparing to an earlier scheduled maintenance
              next if o[:ignore]
              next unless (sm[:start_time] < o[:end_time]) &&
                (sm[:end_time] > o[:start_time])

              if sm[:start_time] <= o[:start_time] &&
                sm[:end_time] >= o[:end_time]

                # outage is fully overlapped by the scheduled maintenanc
                o[:ignore] = true

              elsif sm[:start_time] <= o[:start_time]
                # partially overlapping on the earlier side
                o[:start_time] = sm[:end_time]
              elsif sm[:end_time] >= o[:end_time]
                # partially overlapping on the later side
                o[:end_time] = sm[:start_time]
              end
            end

          end

          # sum outage times, unless they are to be ignored
          total_secs = outs.inject(0) {|sum, o|
            sum += (o[:ignore] ? 0 : (o[:end_time] - o[:start_time]))
          }

          percentage = (total_secs * 100) / (end_time - start_time)
        end

        {:total_seconds => total_secs, :percentage => percentage, :downtime => outs}
      end

    end

  end

end