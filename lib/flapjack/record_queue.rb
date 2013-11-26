#!/usr/bin/env ruby

module Flapjack

  class RecordQueue

    def initialize(queue, object_klass)
      @queue = queue
      @object_klass = object_klass
    end

    def push(object)
      Flapjack.redis.multi do
        Flapjack.redis.lpush(@queue, object.id)
        Flapjack.redis.lpush("#{@queue}_actions", "+")
      end
    end

    def foreach(options = {})
      while object_id = Flapjack.redis.rpop(@queue)
        next unless object = @object_klass.find_by_id(object_id)
        yield object if block_given?
        object.destroy unless options[:keep]
      end
    end

    def wait
      Flapjack.redis.brpop("#{@queue}_actions")
    end

  end

end