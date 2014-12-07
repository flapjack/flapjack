# !/usr/bin/env ruby

require 'sandstorm/records/redis_record'

module Flapjack
  module Data
    class Path

      include Sandstorm::Records::RedisRecord

      define_attributes :is_alerting => :boolean

      index_by :alerting

      belongs_to :rule, :class_name => 'Flapjack::Data::Rule',
        :inverse_of => :paths

      has_and_belongs_to_many :checks, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :paths

    end
  end
end