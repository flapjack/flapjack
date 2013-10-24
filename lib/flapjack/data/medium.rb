#!/usr/bin/env ruby

require 'sandstorm/record'

module Flapjack

  module Data

    class Medium

      include Sandstorm::Record

      TYPES = ['email', 'sms', 'jabber', 'pagerduty']

      define_attributes :type => :string,
                        :address  => :string,
                        :interval => :integer,
                        :rollup_threshold => :integer

      belongs_to :contact, :class_name => 'Flapjack::Data::Contact'

      has_many :alerting_checks, :class_name => 'Flapjack::Data::Check'

      index_by :type

      validates :type, :presence => true,
        :inclusion => {:in => Flapjack::Data::Medium::TYPES }
      validates :address, :presence => true
      validates :interval, :presence => true,
        :numericality => {:greater_than => 0, :only_integer => true}

      def clean_alerting_checks
        checks_to_remove = alerting_checks.select do |check|
          Flapjack::Data::CheckState.ok_states.include?(check.state) ||
          check.in_unscheduled_maintenance? ||
          check.in_scheduled_maintenance?
        end
        return 0 if checks_to_remove.empty?

        alerting_checks.delete(*checks_to_remove)
        checks_to_remove.size
      end

    end

  end

end