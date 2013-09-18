#!/usr/bin/env ruby

module Flapjack
  module Data
    class MaintenanceR

      include Flapjack::Data::RedisRecord

      define_attributes :timestamp => :timestamp,
                        :duration => :integer,
                        :summary => :string

    end
  end
end