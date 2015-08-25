#!/usr/bin/env ruby

require 'zermelo/records/redis'

module Flapjack
  module Data
    class Condition

      include Comparable

      def <=>(cond)
        return nil unless cond.is_a?(Flapjack::Data::Condition)
        self.priority <=> cond.priority
      end

      # class methods rather than constants, as these may come from config
      # data in the future; name => priority
      def self.healthy
        {
          'ok' => 1
        }
      end

      def self.unhealthy
        {
          'critical' => -3,
          'warning'  => -2,
          'unknown'  => -1
        }
      end

      # NB: not actually persisted; we probably want a non-persisted record type
      # for this case
      include Zermelo::Records::RedisSet

      define_attributes :name      => :string,
                        :priority  => :integer

      validates :name, :presence => true,
        :inclusion => { :in => Flapjack::Data::Condition.healthy.keys +
                               Flapjack::Data::Condition.unhealthy.keys }

      validates :priority, :presence => true,
        :numericality => {:only_integer => true},
        :inclusion => { :in => Flapjack::Data::Condition.healthy.values |
                               Flapjack::Data::Condition.unhealthy.values }

      before_create :save_allowed?
      before_update :save_allowed?
      def save_allowed?
        false
      end

      def self.healthy?(c)
        self.healthy.keys.include?(c)
      end

      def self.most_unhealthy
        self.unhealthy.min_by {|_, pri| pri }.first
      end

      def self.for_name(n)
        c = Flapjack::Data::Condition.new(:name => n,
          :priority => self.healthy[n.to_s] || self.unhealthy[n.to_s] )
        c.valid? ? c : nil
      end

    end
  end
end