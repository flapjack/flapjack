#!/usr/bin/env ruby

require 'sandstorm/records/redis_record'

# TODO whenever a check's tags change, or a rule's tags change,
# delete all routes belonging to that check/rule and recreate them
# according to the new tags

# then the check/rule lookup can be massively simplified, as can
# the 'alerting route' stuff (that boolean would need to be updated
# on any healthy -> unhealthy or unhealthy -> healthy transition,
# as well as on ack.)

module Flapjack
  module Data
    class Route

      include Sandstorm::Records::RedisRecord

      define_attributes :conditions_list => :string,
                        :is_alerting => :boolean

      index_by :conditions_list, :is_alerting

      belongs_to :rule, :class_name => 'Flapjack::Data::Rule',
        :inverse_of => :routes

      has_and_belongs_to_many :checks, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :routes

    end
  end
end