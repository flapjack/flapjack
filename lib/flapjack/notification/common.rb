#!/usr/bin/env ruby
#

module Flapjack
  module Notification

    module Common

      def perform(notification)
        Flapjack.bootstrap
        @log = Flapjack.logger
        @persistence = Flapjack.persistence

        @log.debug "Woo, got a notification to send out: #{notification.inspect}"
        dispatch(notification)
      end

    end
  end
end

