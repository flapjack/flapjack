#!/usr/bin/env ruby

require 'zermelo/records/redis'

require 'flapjack/data/condition'

module Flapjack
  module Data
    class State

      include Zermelo::Records::Redis

      define_attributes :timestamp => :timestamp,
                        :condition => :string

      index_by :condition
      range_index_by :timestamp

      belongs_to :check, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :states

      belongs_to :most_severe_check, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :most_severe

      has_sorted_set :entries, :class_name => 'Flapjack::Data::Entry',
        :key => :timestamp, :inverse_of => :state,
        :after_add => :update_check_last_update

      def update_check_last_update(e)
        self.check.last_update = e.timestamp
        self.check.summary     = e.summary
      end

      validates :timestamp, :presence => true

      # condition shopuld only be blank if no previous check states with condition
      validates :condition, :allow_blank => true,
        :inclusion => { :in => Flapjack::Data::Condition.healthy.keys +
                               Flapjack::Data::Condition.unhealthy.keys }

    end
  end
end
