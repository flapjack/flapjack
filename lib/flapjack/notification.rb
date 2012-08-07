#!/usr/bin/env ruby
#

module Flapjack
  class Notification

    def self.perform(notification)
      #Flapjack.bootstrap(:logger => "notification")
      Flapjack.bootstrap
      @log = Flapjack.logger
      @log.debug "Woo, got a notification to send out: #{notification.inspect}"
      sendit(notification)
    end

  end
end

