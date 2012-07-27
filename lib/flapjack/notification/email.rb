#!/usr/bin/env ruby

module Flapjack
  class Notification::Email < Notification
    @queue = :email_notifications

    def self.sendit(notification)
      puts "Sending email notification now (not for realz)"
    end

  end
end

