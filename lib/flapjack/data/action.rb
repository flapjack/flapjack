#!/usr/bin/env ruby

require 'sandstorm/records/redis_record'

module Flapjack
  module Data
    class Action

      include Sandstorm::Records::RedisRecord

      define_attributes :action    => :string,
                        :timestamp => :timestamp

      index_by :action

      belongs_to :check, :class_name => 'Flapjack::Data::Check', :inverse_of => :actions

      def self.all_actions
        ['acknowledgement', 'test_notifications']
      end

      validate :action, :presence => true, :inclusion => { :in => self.all_actions }
      validate :timestamp, :presence => true

    end
  end
end