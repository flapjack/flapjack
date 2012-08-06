#!/usr/bin/env ruby

require 'flapjack/notification/sms_messagenet'

module Flapjack
  class Notification::Sms < Flapjack::Notification
    @queue = :sms_notifications

    def self.sendit(notification)
      notification_type  = notification['notification_type']
      contact_first_name = notification['contact_first_name']
      contact_last_name  = notification['contact_last_name']
      state              = notification['state']
      summary            = notification['summary']
      entity, check      = notification['event_id'].split(':')

      puts "Sending sms notification now"
      headline{'problem'         => 'PROBLEM: ',
               'recovery'        => 'RECOVERY: ',
               'acknowledgement' => 'ACK: ',
               'unknown'         => '' }
               ''                => '' }

      notification_type

      message += "#{headline[notification_type]}'#{check}' on #{entity} is #{state.upcase} at #{when.strftime('%H:%M %d %b')}, #{summary}"
      notification['message'] = message
      Flapjack::Notification::SmsMessagenet.sender(notification)
    end

  end
end

