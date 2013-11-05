#!/usr/bin/env ruby

require 'sandstorm/record'

module Flapjack
  module Data
    class ScheduledMaintenance

        include Sandstorm::Record

        define_attributes :start_time => :timestamp,
                          :end_time   => :timestamp,
                          :summary    => :string

        validates :start_time, :presence => true
        validates :end_time, :presence => true

        belongs_to :check_by_start, :class_name => 'Flapjack::Data::Check',
          :inverse_of => :scheduled_maintenances_by_start

        belongs_to :check_by_end, :class_name => 'Flapjack::Data::Check',
          :inverse_of => :scheduled_maintenances_by_end

        def duration
          self.end_time - self.start_time
        end

    end
  end
end