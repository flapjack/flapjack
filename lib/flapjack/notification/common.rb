#!/usr/bin/env ruby

require 'flapjack/pikelet'

module Flapjack
  module Notification

    module Common

      include Flapjack::Pikelet

      def perform(notification)
        self.bootstrap
        @logger.debug "Woo, got a notification to send out: #{notification.inspect}"
        dispatch(notification)
      end

    end
  end
end

