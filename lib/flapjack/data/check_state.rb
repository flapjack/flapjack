#!/usr/bin/env ruby

require 'sandstorm/records/redis_record'

module Flapjack
  module Data
    class CheckState

      include Sandstorm::Records::RedisRecord

      define_attributes :state     => :string,
                        :summary   => :string,
                        :details   => :string,
                        :count     => :integer,
                        :timestamp => :timestamp,
                        :notified  => :boolean,
                        :last_notification_count => :integer

      unique_index_by :count
      index_by :state, :notified

      belongs_to :check, :class_name => 'Flapjack::Data::Check', :inverse_of => :states

      has_many :current_notifications, :class_name => 'Flapjack::Data::Notification',
        :inverse_of => :state
      has_many :previous_notifications, :class_name => 'Flapjack::Data::Notification',
        :inverse_of => :previous_state

      def self.ok_states
        ['ok']
      end

      def self.failing_states
        ['critical', 'warning', 'unknown']
      end

      # TODO make these dynamic, configured, created on start if not present
      # this object will then reference them rather than use a string
      def self.all_states
        self.failing_states + self.ok_states
      end

      validate :state, :presence => true, :inclusion => { :in => self.all_states }
      validate :timestamp, :presence => true

    end
  end
end