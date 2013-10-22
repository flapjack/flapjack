#!/usr/bin/env ruby

require 'sandstorm/record'

require 'flapjack/data/check_state_r'

module Flapjack
  module Data
    class NotificationBlockR

      include Sandstorm::Record

      define_attributes :expire_at        => :timestamp,
                        :media_type       => :string,     # may be nil
                        :entity_check_id  => :id,         # may be nil
                        :state            => :string      # may be nil

      index_by :media_type, :entity_check_id, :state

      belongs_to :contact, :class_name => 'Flapjack::Data::ContactR'

      validate :expire_at, :presence => true
      validate :state,
        :inclusion => { :in => Flapjack::Data::CheckStateR.all_states, :allow_blank => true }

    end
  end
end
