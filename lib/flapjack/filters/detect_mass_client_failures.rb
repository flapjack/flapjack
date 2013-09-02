#!/usr/bin/env ruby

require 'flapjack/filters/base'

module Flapjack
  module Filters

    # * If the service event’s state is a failure, and the total number of failing client checks is
    #   over a threshold (e.g. 10 checks are failing), then set a meta flag noting the threshold has
    #   been tripped, and generate an event for this meta check
    # * If the service event’s state is ok, and the meta flag is set, and the total number of
    #   failing client checks is less than a threshold (eg 10), then unset the flag, and generate an
    #   event for this meta check
    class DetectMassClientFailures
      include Base

      def block?(event, entity_check, previous_state)
        client_mass_fail_threshold = 10
        timestamp = Time.now.to_i

        if event.service?
          client_fail_count = @redis.zcount("failed_checks:#{event.client}", '-inf', '+inf')

          if client_fail_count >= client_mass_fail_threshold
            # set the flag
            # FIXME: perhaps implement this with tagging
            @redis.add("mass_failed_client:#{event.client}", timestamp)
            @redis.zadd("mass_failure_events_client:#{event.client}", 0, timestamp)
          else
            # unset the flag
            start_mf = @redis.get("mass_failed_client:#{event.client}")
            duration = Time.now.to_i - start_mf.to_i
            @redis.del("mass_failed_client:#{event.client}")
            @redis.zadd("mass_failure_events_client:#{event.client}", duration, start_mf)
          end
        end

        result = false
        @logger.debug("Filter: DetectMassClientFailures: #{result ? "block" : "pass"}")
        result
      end
    end
  end
end
