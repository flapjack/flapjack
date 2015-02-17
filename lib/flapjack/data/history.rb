#!/usr/bin/env ruby

require 'zermelo/records/redis_record'

require 'flapjack/data/condition'

module Flapjack
  module Data
    class History

      include Zermelo::Records::InfluxDBRecord

      define_attributes :timestamp     => :timestamp,
                        :condition     => :string,
                        :action        => :string,
                        :summary       => :string,
                        :details       => :string,
                        :perfdata_json => :string

      index_by :condition, :action

      belongs_to :check, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :states

      validates :timestamp, :presence => true

      # condition should only be blank if no previous states with condition
      validates :condition, :allow_blank => true,
        :inclusion => { :in => Flapjack::Data::Condition.healthy.keys +
                               Flapjack::Data::Condition.unhealthy.keys }

      ACTIONS = %w(acknowledgement test_notifications)
      validates :action, :allow_nil => true,
        :inclusion => {:in => Flapjack::Data::Entry::ACTIONS}

    end
  end
end
