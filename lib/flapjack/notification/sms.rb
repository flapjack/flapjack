#!/usr/bin/env ruby

module Flapjack
  class Notification::Sms < Flapjack::Notification
    @queue = :sms_notifications

    def self.sendit(notification)
      puts "Sending sms notification now (not for realz)"
    end

  end
end

