#!/usr/bin/env ruby

module Flapjack
  class Notification::Email < Flapjack::Notification
    @queue = :email_notifications

    def send(notification)
      puts "Sending email notification now (not for realz)"
    end

  end
end

