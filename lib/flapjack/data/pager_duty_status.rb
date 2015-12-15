#!/usr/bin/env ruby

require 'zermelo/records/redis'

require 'flapjack/data/validators/id_validator'

module Flapjack
  module Data
    class PagerDutyStatus
      include Zermelo::Records::RedisSet

      define_attributes :locked       => :boolean,
                        :updated_at   => :timestamp

      validates_with Flapjack::Data::Validators::IdValidator

      validates :locked, :inclusion => {:in => [true, false]}
      validates :updated_at, :presence => true
    end
  end
end

