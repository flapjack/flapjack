#!/usr/bin/env ruby

module Flapjack
  module Notification

    class Jabber

      include Flapjack::Pikelet

      def initialize(opts)
        self.bootstrap
      end

      def main
        puts "in main jabber"
      end

      def dispatch(notification)

        notification_type  = notification['notification_type']
        contact_first_name = notification['contact_first_name']
        contact_last_name  = notification['contact_last_name']
        state              = notification['state']
        summary            = notification['summary']
        time               = notification['time']
        entity, check      = notification['event_id'].split(':')

      end

    end
  end
end

