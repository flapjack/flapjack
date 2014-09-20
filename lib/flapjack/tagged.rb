#!/usr/bin/env ruby

require 'flapjack/data/tag'
require 'flapjack/data/tag_set'

# mixed in to some of the Flapjack data classes

module Flapjack

  module Tagged

    def tag_prefix
      self.class.name.split('::').last.downcase + '_tag'
    end

    # return the set of tags for this object
    def tags
      @tags ||= Flapjack::Data::TagSet.new( @redis.keys("#{tag_prefix}:*").inject([]) {|memo, tag|
        if Flapjack::Data::Tag.find(tag, :redis => @redis).include?(@id.to_s)
          memo << tag.sub(/^#{tag_prefix}:/, '')
        end
        memo
      } )
    end

    # adds tags to this object
    def add_tags(*enum)
      enum.each do |t|
        Flapjack::Data::Tag.create("#{tag_prefix}:#{t}", [@id], :redis => @redis)
        tags.add(t)
      end
    end

    # removes tags from this object
    def delete_tags(*enum)
      enum.each do |t|
        tag = Flapjack::Data::Tag.find("#{tag_prefix}:#{t}", :redis => @redis)
        tag.delete(@id)
        tags.delete(t)
      end
    end

  end

end