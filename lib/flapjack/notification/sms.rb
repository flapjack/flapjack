#!/usr/bin/env ruby

require 'flapjack/notification/sms/messagenet'

module Flapjack
  module Notification

    class Sms
      extend Flapjack::Notification::Common

      def self.dispatch(notification, opts = {})
        notification_type  = notification['notification_type']
        contact_first_name = notification['contact_first_name']
        contact_last_name  = notification['contact_last_name']
        state              = notification['state']
        summary            = notification['summary']
        time               = notification['time']
        entity, check      = notification['event_id'].split(':')

        headline_map = {'problem'         => 'PROBLEM: ',
                        'recovery'        => 'RECOVERY: ',
                        'acknowledgement' => 'ACK: ',
                        'unknown'         => '',
                        'test'            => 'TEST NOTIFICATION: ',
                        ''                => '',
                       }

        headline = headline_map[notification_type] || ''

        message = "#{headline}'#{check}' on #{entity}"
        message += " is #{state.upcase}" unless notification_type == 'acknowledgement'
        message += " at #{Time.at(time).strftime('%-d %b %H:%M')}, #{summary}"

        notification['message'] = message
        Flapjack::Notification::Sms::Messagenet.sender(notification,
          :logger => opts[:logger],
          :config => Flapjack::Notification::Sms.class_variable_get('@@config'))
      end

    end
  end
end

