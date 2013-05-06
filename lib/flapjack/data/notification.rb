#!/usr/bin/env ruby

require 'flapjack/data/message'

module Flapjack
  module Data
    class Notification

      attr_accessor :event, :type, :max_notified_severity

      def self.for_event(event, opts = {})
        self.new(:event => event,
                 :type => opts[:type],
                 :max_notified_severity => opts[:max_notified_severity])
      end

      def messages(opts = {})
        contacts = opts[:contacts]
        return [] if contacts.nil?
        @messages ||= contacts.collect {|contact|
          contact.media.keys.inject([]) { |ret, mk|
            m = Flapjack::Data::Message.for_contact(:contact => contact)
            m.notification = self
            m.medium  = mk
            m.address = contact.media[mk]
            ret << m
            ret
          }
        }.flatten
      end

      def contents
        @contents ||= {'event_id'              => event.id,
                       'state'                 => event.state,
                       'summary'               => event.summary,
                       'time'                  => event.time,
                       'duration'              => event.duration || nil,
                       'notification_type'     => type,
                       'max_notified_severity' => max_notified_severity }
      end

    private

      def initialize(opts = {})
        raise "Event not passed" unless event = opts[:event]
        @event = event
        @type  = opts[:type]
        @max_notified_severity = opts[:max_notified_severity]
      end

    end
  end
end

