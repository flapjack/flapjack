#!/usr/bin/env ruby
#

module Flapjack
  class Notification

    def self.perform(notification)
      puts "Woo, got a notification to send out: #{notification.inspect}"
      send(notification)
         # notification = { :event_id           => event.id,
         #                  :state              => event.state,
         #                  :summary            => event.summary,
         #                  :notification_type  => notification_type,
         #                  :contact_id         => contact_id,
         #                  :contact_first_name => @persistence.hget("contact:#{contact_id}", 'first_name'),
         #                  :contact_last_name  => @persistence.hget("contact:#{contact_id}", 'last_name'),
         #                  :media              => media,
         #                  :address            => address }
    end

  end
end

