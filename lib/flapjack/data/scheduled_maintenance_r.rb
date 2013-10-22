#!/usr/bin/env ruby

require 'sandstorm/record'

module Flapjack
  module Data
    class ScheduledMaintenanceR

        include Sandstorm::Record

        define_attributes :start_time => :timestamp,
                          :end_time   => :timestamp,
                          :summary    => :string

        validates :start_time, :presence => true
        validates :end_time, :presence => true

        belongs_to :entity_check, :class_name => 'Flapjack::Data::EntityCheckR'

        def duration
          self.end_time - self.start_time
        end

    end
  end
end