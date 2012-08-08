#!/usr/bin/env ruby

require 'flapjack/notification/sms_messagenet'

module Flapjack
  module Notification

    class Sms

      extend Flapjack::Notification::Common

      @queue = :sms_notifications

      def self.dispatch(notification)
        notification_type  = notification['notification_type']
        contact_first_name = notification['contact_first_name']
        contact_last_name  = notification['contact_last_name']
        state              = notification['state']
        summary            = notification['summary']
        time               = notification['time']
        entity, check      = notification['event_id'].split(':')

        puts "Sending sms notification now"
        headline_map = {'problem'         => 'PROBLEM: ',
                        'recovery'        => 'RECOVERY: ',
                        'acknowledgement' => 'ACK: ',
                        'unknown'         => '',
                        ''                => '',
                       }

        headline = headline_map[notification_type] || ''

        message = "#{headline}'#{check}' on #{entity} is #{state.upcase} at #{Time.at(time).strftime('%-d %b %H:%M')}, #{summary}"
        notification['message'] = message
        Flapjack::Notification::SmsMessagenet.sender(notification, @log)
      end

    end
  end
end

