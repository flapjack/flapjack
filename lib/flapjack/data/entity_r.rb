#!/usr/bin/env ruby

require 'flapjack/data/contact_r'

module Flapjack

  module Data

    class EntityR

      include Flapjack::Data::RedisRecord

      define_attributes :name => :string,
                        :tags => :set

      index_by :name

      has_many :contacts, :class => Flapjack::Data::ContactR

      # NB replaces check_list, check_count
      # TODO
      # has_many :checks, :class => Flapjack::Data::EntityCheckR


      # TODO change uses of Entity.all to EntityR.all.sort_by(&:name)

      # TODO change uses of Entity.find_by_name(N) to EntityR.find_by(:name, N)



    #   # NB: if we're worried about user input, https://github.com/mudge/re2
    #   # has bindings for a non-backtracking RE engine that runs in linear
    #   # time
    #   def self.find_all_name_matching(pattern)
    #     begin
    #       regex = /#{pattern}/
    #     rescue => e
    #       if @logger
    #         @logger.info("Jabber#self.find_all_name_matching - unable to use /#{pattern}/ as a regex pattern: #{e}")
    #       end
    #       return nil
    #     end
    #     Flapjack.redis.keys('entity_id:*').inject([]) {|memo, check|
    #       a, entity_name = check.split(':', 2)
    #       if (entity_name =~ regex) && !memo.include?(entity_name)
    #         memo << entity_name
    #       end
    #       memo
    #     }.sort
    #   end

    #   def self.find_all_with_tags(tags, options = {})
    #     tags_prefixed = tags.collect {|tag|
    #       "#{TAG_PREFIX}:#{tag}"
    #     }
    #     logger.debug "tags_prefixed: #{tags_prefixed.inspect}" if logger = options[:logger]
    #     Flapjack::Data::Tag.find_intersection(tags_prefixed).collect {|entity_id|
    #       Flapjack::Data::Entity.find_by_id(entity_id).name
    #     }.compact
    #   end

    #   def self.find_all_with_checks
    #     Flapjack.redis.zrange("current_entities", 0, -1)
    #   end


    # TODO seems odd to call into another class for this -- maybe reverse them?
    # TODO once EntityCheckR is done this should be trivially retrievable by a
    # keys('*') query
    #   def self.find_all_with_failing_checks
    #     Flapjack::Data::EntityCheck.find_all_failing_by_entity.keys
    #   end

    end

  end

end
