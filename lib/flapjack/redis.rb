#!/usr/bin/env ruby

# redis interaction functions for flapjack
# passed in the redis connection that should be used
module Flapjack
  module Redis

    # takes a key "entity:check", returns true if the check is in unscheduled
    # maintenance
    def in_unscheduled_maintenance?(redis, key)
      redis.exists("#{key}:unscheduled_maintenance")
    end

    # returns true if the check is in scheduled maintenance
    def in_scheduled_maintenance?(redis, key)
      redis.exists("#{key}:scheduled_maintenance")
    end

    # creates an event object and adds it to the events list in redis
    #   'entity'    => entity,
    #   'check'     => check,
    #   'type'      => 'service',
    #   'state'     => state,
    #   'summary'   => check_output,
    #   'time'      => timestamp,
    def create_event(redis, event)
      redis.rpush('events', Yajl::Encoder.encode(event))
    end

    def create_acknowledgement(redis, check_id, opts={})
      defaults = {
        'summary' => '...',
      }
      options = defaults.merge(opts)

      entity, check = check_id.split(':')
      event = { 'entity'  => entity,
                'check'   => check,
                'type'    => 'action',
                'state'   => 'acknowledgement',
                'time'    => Time.now.to_i,
                'summary' => options['summary'],
      }
      create_event(redis, event)
    end

  end
end

