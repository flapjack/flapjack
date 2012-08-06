#!/usr/bin/env ruby

module Flapjack
  class Notification::Sms < Flapjack::Notification
    @queue = :sms_notifications

    def self.sendit(notification)
      notification_type  = notification[:notification_type]
      contact_first_name = notification[:contact_first_name]
      contact_last_name  = notification[:contact_last_name]
      entity, check      = notification[:event_id].split(':')

      puts "Sending sms notification now"

      case notification_type
      when 'problem'
        message = "PROBLEM: "
      when 'recovery'

      when 'acknowledgement'
      end

      Flapjack::Notification::SmsMessagenet.sender(notification)
    end

  end
end

