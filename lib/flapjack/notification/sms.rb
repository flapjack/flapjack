#!/usr/bin/env ruby

require 'flapjack/pikelet'
require 'flapjack/notification/sms/messagenet'

module Flapjack
  module Notification

    class Sms

      extend Flapjack::ResquePikelet

      class << self

        def perform(notification)
          @logger.debug "Woo, got a notification to send out: #{notification.inspect}"
          dispatch(notification, :logger => @logger, :redis => ::Resque.redis)
        end

        def dispatch(notification, opts = {})
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
                          'test'            => 'TEST NOTIFICATION: ',
                          'unknown'         => '',
                          ''                => '',
                         }

          headline = headline_map[notification_type] || ''

          message = "#{headline}'#{check}' on #{entity}"
          message += " is #{state.upcase}" unless ['acknowledgement', 'test'].include?(notification_type)
          message += " at #{Time.at(time).strftime('%-d %b %H:%M')}, #{summary}"

          notification['message'] = message
          Flapjack::Notification::Sms::Messagenet.sender(notification,
            :logger => opts[:logger],
            :config => Flapjack::Notification::Sms.instance_variable_get('@config'))
        end

      end

    end
  end
end

