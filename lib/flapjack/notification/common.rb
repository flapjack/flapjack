#!/usr/bin/env ruby

require 'flapjack/pikelet'

module Flapjack
  module Notification

    module Common

      include Flapjack::Pikelet

      # NB: these probably shouldn't initialise Redis
      def perform(notification)
        bootstrap(:redis => {:driver => :ruby})
        @logger.debug "Woo, got a notification to send out: #{notification.inspect}"
        dispatch(notification, :logger => @logger)
      end

    end
  end
end

