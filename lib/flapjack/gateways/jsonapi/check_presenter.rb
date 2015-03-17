#!/usr/bin/env ruby

# Formats entity/check data for presentation by the API methods in Flapjack::Gateways::API.

require 'sinatra/base'

require 'flapjack/data/entity_check'

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      class CheckPresenter

        def initialize(entity_check)
          @entity_check = entity_check
        end

        def status
          {'name'                              => @entity_check.check,
           'state'                             => @entity_check.state,
           'enabled'                           => @entity_check.enabled?,
           'summary'                           => @entity_check.summary,
           'details'                           => @entity_check.details,
           'perfdata'                          => @entity_check.perfdata,
           'in_unscheduled_maintenance'        => @entity_check.in_unscheduled_maintenance?,
           'in_scheduled_maintenance'          => @entity_check.in_scheduled_maintenance?,
           'initial_failure_delay'             => @entity_check.initial_failure_delay,
           'repeat_failure_delay'              => @entity_check.repeat_failure_delay,
           'last_update'                       => @entity_check.last_update,
           'last_change'                       => @entity_check.last_change,
           'last_problem_notification'         => @entity_check.last_notification_for_state(:problem)[:timestamp],
           'last_recovery_notification'        => @entity_check.last_notification_for_state(:recovery)[:timestamp],
           'last_acknowledgement_notification' => @entity_check.last_notification_for_state(:acknowledgement)[:timestamp]}
        end

        def outage(start_time, end_time, options = {})
          # hist_states is an array of hashes, with [state, timestamp, summary] keys
          hist_states = @entity_check.historical_states(start_time, end_time)
          return {:outages => []} if hist_states.empty?

          initial = @entity_check.historical_state_before(hist_states.first[:timestamp])
          hist_states.unshift(initial) if initial

          # TODO the following works, but isn't the neatest
          num_states = hist_states.size

          index = 0
          result = []
          obj = nil

          while index < num_states do
            last_obj = obj
            obj = hist_states[index]
            index += 1

            next if obj[:state] == 'ok'

            if last_obj && (last_obj[:state] == obj[:state])
              # TODO maybe build up arrays of these instead, and leave calling
              # classes to join them together if needed?
              result.last[:summary] << " / #{obj[:summary]}"
              result.last[:details] << " / #{obj[:details]}"
              next
            end

            ts = obj[:timestamp]

            obj_st  = (last_obj || !start_time) ? ts : [ts, start_time].max

            next_ts_obj = hist_states[index..-1].detect {|hs| hs[:state] != obj[:state] }
            obj_et  = next_ts_obj ? next_ts_obj[:timestamp] : end_time

            obj_dur = obj_et ? obj_et - obj_st : nil

            result << {:state      => obj[:state],
                       :start_time => obj_st,
                       :end_time   => obj_et,
                       :duration   => obj_dur,
                       :summary    => obj[:summary] || '',
                       :details    => obj[:details] || ''
                      }
          end

          {:outages => result}
        end

        def unscheduled_maintenance(start_time, end_time)
          # unsched_maintenance is an array of hashes, with [duration, timestamp, summary] keys
          unsched_maintenance = @entity_check.maintenances(start_time, end_time,
            :scheduled => false)

          # to see if we start in an unscheduled maintenance period, we must check all unscheduled
          # maintenances before the period and their durations
          start_in_unsched = start_time.nil? ? [] :
            @entity_check.maintenances(nil, start_time, :scheduled => false).select {|pu|
              pu[:end_time] >= start_time
            }

          {:unscheduled_maintenances => (start_in_unsched + unsched_maintenance)}
        end

        def scheduled_maintenance(start_time, end_time)
          # sched_maintenance is an array of hashes, with [duration, timestamp, summary] keys
          sched_maintenance = @entity_check.maintenances(start_time, end_time,
            :scheduled => true)

          # to see if we start in a scheduled maintenance period, we must check all scheduled
          # maintenances before the period and their durations
          start_in_sched = start_time.nil? ? [] :
            @entity_check.maintenances(nil, start_time, :scheduled => true).select {|ps|
              ps[:end_time] >= start_time
            }

          {:scheduled_maintenances => (start_in_sched + sched_maintenance)}
        end

        # TODO test whether the below overlapping logic is prone to off-by-one
        # errors; the numbers may line up more neatly if we consider outages to
        # start one second after the maintenance period ends.
        #
        # TODO test performance with larger data sets
        def downtime(start_time, end_time)
          outs = outage(start_time, end_time)[:outages]

          total_secs  = {}
          percentages = {}

          outs.collect {|obj| obj[:state]}.uniq.each do |st|
            total_secs[st]  = 0
            percentages[st] = (start_time.nil? || end_time.nil?) ? nil : 0
          end

          unless outs.empty?

            # Initially we need to check for cases where a scheduled
            # maintenance period is fully covered by an outage period.
            # We then create two new outage periods to cover the time around
            # the scheduled maintenance period, and remove the original.

            sched_maintenances = scheduled_maintenance(start_time, end_time)[:scheduled_maintenances]

            sched_maintenances.each do |sm|

              split_outs = []

              outs.each { |o|
                next unless o[:end_time] && (o[:start_time] < sm[:start_time]) &&
                  (o[:end_time] > sm[:end_time])
                o[:delete] = true
                split_outs += [{:state => o[:state],
                                :start_time => o[:start_time],
                                :end_time => sm[:start_time],
                                :duration => sm[:start_time] - o[:start_time],
                                :summary => "#{o[:summary]} [split start]"},
                               {:state => o[:state],
                                :start_time => sm[:end_time],
                                :end_time => o[:end_time],
                                :duration => o[:end_time] - sm[:end_time],
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
                next unless o[:end_time] && (sm[:start_time] < o[:end_time]) &&
                  (sm[:end_time] > o[:start_time])

                if sm[:start_time] <= o[:start_time] &&
                  sm[:end_time] >= o[:end_time]

                  # outage is fully overlapped by the scheduled maintenance
                  o[:delete] = true

                elsif sm[:start_time] <= o[:start_time]
                  # partially overlapping on the earlier side
                  o[:start_time] = sm[:end_time]
                  o[:duration] = o[:end_time] - o[:start_time]
                elsif sm[:end_time] >= o[:end_time]
                  # partially overlapping on the later side
                  o[:end_time] = sm[:start_time]
                  o[:duration] = o[:end_time] - o[:start_time]
                end
              end

              outs.reject! {|o| o[:delete]}
            end

            total_secs = outs.inject(total_secs) {|ret, o|
              ret[o[:state]] += o[:duration] if o[:duration]
              ret
            }

            unless (start_time.nil? || end_time.nil?)
              total_secs.each_pair do |st, ts|
                percentages[st] = (total_secs[st] * 100.0) / (end_time.to_f - start_time.to_f)
              end
              total_secs['ok'] = (end_time - start_time) - total_secs.values.reduce(:+)
              percentages['ok'] = 100 - percentages.values.reduce(:+)
            end
          end

          {:total_seconds => total_secs, :percentages => percentages, :downtime => outs}
        end

      end

    end

  end

end
