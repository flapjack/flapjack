#!/usr/bin/env ruby

# 'Notification' refers to the template object created when an event occurs,
# from which individual 'Message' objects are created, one for each
# contact+media recipient.

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
        @id = self.object_id.to_i.to_s + '-' + t.to_i.to_s + '.' + t.tv_usec.to_s
      end

      def contents
        c = {'contact_id'         => contact.id,
             'contact_first_name' => contact.first_name,
             'contact_last_name'  => contact.last_name,
             'media'              => medium,
             'address'            => address,
             'id'                 => id
            }
        c['duration'] = duration if duration
        c.merge(notification.contents)
      end

    private

      def initialize(opts = {})
        @contact = opts[:contact]
      end

    end
  end
end

