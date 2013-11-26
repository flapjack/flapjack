#!/usr/bin/env ruby

module Flapjack
  module Data
    class RollupAlert

      include Sandstorm::Record

      define_attributes :state    => :string,
                        :duration => :integer

      index_by :state

      belongs_to :check, :class_name => 'Flapjack::Data::Check', :inverse_of => :rollup_alerts
      belongs_to :alert, :class_name => 'Flapjack::Data::Alert', :inverse_of => :rollup_alerts

      def self.states
        ['critical', 'warning', 'unknown']
      end

      validates :state, :presence => true, :inclusion => {:in => self.states }
      validates :duration, :numericality => {:minimum => 0}
    end
  end
end