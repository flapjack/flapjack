#!/usr/bin/env ruby

require 'sandstorm/record'

module Flapjack
  module Data
    class UnscheduledMaintenance

      include Sandstorm::Record

      define_attributes :start_time => :timestamp,
                        :end_time   => :timestamp,
                        :summary    => :string,
                        :notified   => :boolean,
                        :last_notification_count => :integer

      index_by :notified

      validates :start_time, :presence => true
      validates :end_time, :presence => true

      belongs_to :check_by_start, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :unscheduled_maintenances_by_start

      belongs_to :check_by_end, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :unscheduled_maintenances_by_end

      def duration
        self.end_time - self.start_time
      end

    end
  end
end