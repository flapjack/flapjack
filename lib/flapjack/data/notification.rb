#!/usr/bin/env ruby

# 'Notification' refers to the template object created when an event occurs,
# from which individual 'Message' objects are created, one for each
# contact+media recipient.

require 'zermelo/records/redis'

require 'flapjack/data/alert'
require 'flapjack/data/contact'

module Flapjack
  module Data
    class Notification

      include Zermelo::Records::Redis

      define_attributes :severity       => :string,
                        :duration       => :integer,
                        :condition_duration => :float,
                        :event_hash     => :string

      belongs_to :entry, :class_name => 'Flapjack::Data::Entry',
        :inverse_of => :notification

      validates :severity,
        :inclusion => {:in => Flapjack::Data::Condition.unhealthy.keys +
                              Flapjack::Data::Condition.healthy.keys }

    end
  end
end
