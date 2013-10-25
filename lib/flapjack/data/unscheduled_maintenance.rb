#!/usr/bin/env ruby

require 'sandstorm/record'

module Flapjack
  module Data
    class UnscheduledMaintenance

      include Sandstorm::Record

      define_attributes :start_time => :timestamp,
                        :end_time   => :timestamp,
                        :summary    => :string,
                        :notified  => :boolean,
                        :last_notification_count => :integer

      index_by :notified

      validates :start_time, :presence => true
      validates :end_time, :presence => true

      belongs_to :entity_check, :class_name => 'Flapjack::Data::Check'

      def duration
        self.end_time - self.start_time
      end

    end
  end
end