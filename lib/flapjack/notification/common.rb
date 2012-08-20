#!/usr/bin/env ruby

require 'flapjack/pikelet'

module Flapjack
  module Notification

    module Common

      include Flapjack::Pikelet

      def perform(notification)
        bootstrap(:evented => defined?(EVENTED_RESQUE)) # not ideal
        @logger.debug "Woo, got a notification to send out: #{notification.inspect}"
        dispatch(notification, :logger => @logger)
      end

    end
  end
end

