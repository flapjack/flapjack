#!/usr/bin/env ruby

require 'flapjack/data/unscheduled_maintenance'

require 'flapjack/filters/base'

module Flapjack
  module Filters
    # * If the action event’s state is an acknowledgement, and the corresponding check is in a
    #   failure state, then set unscheduled maintenance for 4 hours on the check
    # * If the action event’s state is an acknowledgement, and the corresponding check is not in a
    #   failure state, then don’t alert
    class Acknowledgement
      include Base

      def block?(check, opts = {})
        old_state = opts[:old_state]
        new_state = opts[:new_state]
        timestamp = opts[:timestamp]

        label = 'Filter: Acknowledgement:'

        unless 'acknowledgement'.eql?(new_state.action)
          Flapjack.logger.debug { "#{label} pass (not an ack)" }
          return false
        end

        if old_state.nil? || Flapjack::Data::Condition.healthy?(old_state.condition)
          Flapjack.logger.debug {
            "#{label} blocking because check '#{check.name}' is not failing"
          }
          return true
        end

        end_time = timestamp + (opts[:duration] || (4 * 60 * 60))

        unsched_maint = Flapjack::Data::UnscheduledMaintenance.new(:start_time => timestamp,
          :end_time => end_time, :summary => new_state.summary)
        unsched_maint.save

        check.set_unscheduled_maintenance(unsched_maint)

        Flapjack.logger.debug{
          "#{label} pass (unscheduled maintenance created for #{check.name}, " \
          " duration: #{end_time - timestamp})"
        }
        false
      end
    end
  end
end
