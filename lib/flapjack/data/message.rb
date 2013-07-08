#!/usr/bin/env ruby

# 'Notification' refers to the template object created when an event occurs,
# from which individual 'Message' objects are created, one for each
# contact+media recipient.

require 'flapjack/data/contact'
require 'flapjack/data/notification'

module Flapjack
  module Data
    class Message

      attr_reader :medium, :address, :duration, :contact

      def self.for_contact(contact, opts = {})
        self.new(:contact => contact,
                 :notification_contents => opts[:notification_contents],
                 :medium => opts[:medium],
                 :address => opts[:address],
                 :duration => opts[:duration])
      end

      def id
        return @id if @id
        t = Time.now
        # FIXME: consider using a UUID here
        # this is planned to be used as part of alert history keys
        @id = "#{self.object_id.to_i}-#{t.to_i}.#{t.tv_usec}"
      end

      def contents
        c = {'media'              => medium,
             'address'            => address,
             'id'                 => id,
             'contact_id'         => contact.id,
             'contact_first_name' => contact.first_name,
             'contact_last_name'  => contact.last_name}
        c['duration'] = duration if duration
        return c if @notification_contents.nil?
        c.merge(@notification_contents)
      end

    private

      def initialize(opts = {})
        @contact = opts[:contact]
        @notification_contents = opts[:notification_contents]
        @medium = opts[:medium]
        @address = opts[:address]
        @duration = opts[:duration]
      end

    end
  end
end

