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
