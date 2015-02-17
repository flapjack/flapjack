#!/usr/bin/env ruby

require 'zermelo/records/redis_record'

require 'flapjack/data/condition'

module Flapjack
  module Data
    class State

      include Zermelo::Records::RedisRecord

      define_attributes :timestamp => :timestamp,
                        :condition => :string

      index_by :condition

      belongs_to :check, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :states

      belongs_to :most_severe_check, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :most_severe

      has_sorted_set :entries, :class_name => 'Flapjack::Data::Entry',
        :key => :timestamp, :inverse_of => :state

      validates :timestamp, :presence => true

      # condition should only be blank if no previous states with condition
      validates :condition, :allow_blank => true,
        :inclusion => { :in => Flapjack::Data::Condition.healthy.keys +
                               Flapjack::Data::Condition.unhealthy.keys }

    end
  end
end
