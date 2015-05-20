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

      define_attributes :severity           => :string,
                        :duration           => :integer,
                        :condition_duration => :float,
                        :event_hash         => :string

      belongs_to :check, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :notifications

      has_one :state, :class_name => 'Flapjack::Data::State',
        :inverse_of => :notification, :after_clear => :destroy_state

      def destroy_state(st)
        # won't be deleted if still referenced elsewhere -- see the State
        # before_destroy callback
        st.destroy
      end

      validates :severity,
        :inclusion => {:in => Flapjack::Data::Condition.unhealthy.keys +
                              Flapjack::Data::Condition.healthy.keys }

    end
  end
end
