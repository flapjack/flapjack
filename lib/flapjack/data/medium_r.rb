#!/usr/bin/env ruby

module Flapjack

  module Data

    class MediumR

      include Flapjack::Data::RedisRecord

      define_attribute_methods [:address, :interval]

      # moved from Contact -- all of these are subsumed by the attributes above

  #     # how often to notify this contact on the given media
  #     # return 15 mins if no value is set
  #     def interval_for_media(media)
  #       interval = Flapjack.redis.hget("contact_media_intervals:#{self.id}", media)
  #       (interval.nil? || (interval.to_i <= 0)) ? (15 * 60) : interval.to_i
  #     end

  #     def set_interval_for_media(media, interval)
  #       if interval.nil?
  #         Flapjack.redis.hdel("contact_media_intervals:#{self.id}", media)
  #         return
  #       end
  #       Flapjack.redis.hset("contact_media_intervals:#{self.id}", media, interval)
  #       self.media_intervals = Flapjack.redis.hgetall("contact_media_intervals:#{self.id}")
  #     end

  #     def set_address_for_media(media, address)
  #       Flapjack.redis.hset("contact_media:#{self.id}", media, address)
  #       if media == 'pagerduty'
  #         # FIXME - work out what to do when changing the pagerduty service key (address)
  #         # probably best solution is to remove the need to have the username and password
  #         # and subdomain as pagerduty's updated api's mean we don't them anymore I think...
  #       end
  #       self.media = Flapjack.redis.hgetall("contact_media:#{@id}")
  #     end

  #     def remove_media(media)
  #       Flapjack.redis.hdel("contact_media:#{self.id}", media)
  #       Flapjack.redis.hdel("contact_media_intervals:#{self.id}", media)
  #       if media == 'pagerduty'
  #         Flapjack.redis.del("contact_pagerduty:#{self.id}")
  #       end
  #     end

    end

  end

end