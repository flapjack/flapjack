#!/usr/bin/env ruby

require 'flapjack/pikelet'

module Flapjack
  module Notification

    module Common

      include Flapjack::Pikelet

      def perform(notification)
        @log.debug "Woo, got a notification to send out: #{notification.inspect}"
        dispatch(notification)
      end

    end
  end
end

