#!/usr/bin/env ruby

# 'Notification' refers to the template object created when an event occurs,
# from which individual 'Message' objects are created, one for each
# contact+media recipient.

require 'flapjack/data/contact'
require 'flapjack/data/notification'

module Flapjack
  module Data
    class Message

      attr_accessor :medium, :address, :id, :duration, :contact, :notification

      def self.for_contact(opts = {})
        self.new(:contact => opts[:contact])
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
             'id'                 => id}
        if contact
          c.update('contact_id'         => contact.id,
                   'contact_first_name' => contact.first_name,
                   'contact_last_name'  => contact.last_name)
        end
        c['duration'] = duration if duration
        c.update(notification.contents) if notification
      end

    private

      def initialize(opts = {})
        @contact = opts[:contact]
      end

    end
  end
end

