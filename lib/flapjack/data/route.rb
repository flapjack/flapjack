#!/usr/bin/env ruby

require 'zermelo/records/redis'

module Flapjack
  module Data
    class Route

      include Zermelo::Records::Redis

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