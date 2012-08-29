#!/usr/bin/env ruby

require 'flapjack/pikelet'

module Flapjack
  module Notification

    module Common

      include Flapjack::Pikelet

      # TODO to make this testable, work out a supported way to make the passed redis connection
      # use the test db
      def perform(notification)
        bootstrap
        @logger.debug "Woo, got a notification to send out: #{notification.inspect}"
        dispatch(notification, :logger => @logger, :redis => ::Redis.new)
      end

    end
  end
end

