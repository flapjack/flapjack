#!/usr/bin/env ruby

# mixed in to some of the Flapjack data classes

module Flapjack

  module Tagged

    def tag_prefix
      self.class.name.split('::').last.downcase + '_tag'
    end

    def known_key
      "known_tags:#{tag_prefix}"
    end

    # return the set of tags for this object
    def tags
      return @tags unless @tags.nil?
      @tags ||= Set.new( @redis.smembers(known_key).inject([]) {|memo, t|
        tag_key = "#{tag_prefix}:#{t}"
        memo << t if @redis.sismember(tag_key, @id.to_s)
        memo
      })
    end

    # adds tags to this object
    def add_tags(*enum)
      enum.each do |t|
        @redis.sadd(known_key, t)
        @redis.sadd("#{tag_prefix}:#{t}", @id)
        tags.add(t)
      end
    end

    # removes tags from this object
    def delete_tags(*enum)
      enum.each do |t|
        tag_key = "#{tag_prefix}:#{t}"
        @redis.srem(tag_key, @id)
        tags.delete(t)
        @redis.srem(known_key, t) if (@redis.scard(tag_key) == 0)
      end
    end

  end

end