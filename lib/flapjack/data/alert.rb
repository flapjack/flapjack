#!/usr/bin/env ruby

require 'active_support/inflector'

require 'sandstorm/record'

require 'flapjack/utility'

# Alert is the object ready to send to someone, complete with an address and all
# the data with which to render the text of the alert in the appropriate gateway

module Flapjack
  module Data
    class Alert

      include Flapjack::Utility
      include Sandstorm::Record

      define_attributes :state        => :string,
                        :summary      => :string,
                        :details      => :string,

                        :last_state   => :string,
                        :last_summary => :string,

                        :event_count  => :integer,
                        :time         => :timestamp,

                        # shouldn't need this, can calculate from state & last_state
                        :notification_type => :string,

                        :acknowledgement_duration => :integer, # SMELL -- passed in as duration in other code
                        :state_duration => :integer,

                        :tags         => :set,
                        :rollup       => :string,

                        :event_hash   => :string

      belongs_to :medium, :class_name => 'Flapjack::Data::Medium', :inverse_of => :alerts
        # media_type, address, :rollup_threshold retrieved from medium
        # contact_id, first_name, last_name retrieved from medium.contact

      belongs_to :check, :class_name => 'Flapjack::Data::Check', :inverse_of => :alerts
        # entity, in_scheduled_maintenance, in_unscheduled_maintenance retrieved from check

      has_many :rollup_alerts, :class_name => 'Flapjack::Data::RollupAlert'

      def self.states
        ['ok', 'critical', 'warning', 'unknown', 'test_notifications', 'acknowledgement']
      end

      validates :state, :presence => true, :inclusion => {:in => self.states },
        :unless => proc {|n| n.type == 'test'}
      validates :state_duration, :presence => true,
        :numericality => {:minimum => 0}, :unless => proc {|n| n.type == 'test'}

      def type
        case self.rollup
        when "problem"
          "rollup_problem"
        when "recovery"
          "rollup_recovery"
        else
          self.notification_type
        end
      end

      def type_sentence_case
        case type
        when "rollup_problem"
          "Problem summary"
        when "rollup_recovery"
          "Problem summaries finishing"
        else
          type.titleize
        end
      end

      def state_title_case
        ['ok'].include?(self.state) ? self.state.upcase : self.state.titleize
      end

      def last_state_title_case
        ['ok'].include?(self.last_state) ? self.last_state.upcase : self.last_state.titleize
      end

      def rollup_states_summary
        state_counts = rollup_state_counts
        Flapjack::Data::RollupAlert.states.inject([]) do |memo, alert_state|
          next memo unless state_counts[state]
          memo << "#{alert_state.titleize}: #{state_counts[alert_state]}"
          memo
        end.join(', ')
      end

      # produces a textual list of checks that are failing broken down by state, eg:
      # Critical: 'PING' on 'foo-app-01.example.com', 'SSH' on 'foo-app-01.example.com';
      #   Warning: 'Disk / Utilisation' on 'foo-app-02.example.com'
      def rollup_states_detail_text(opts = {})
        state_counts = rollup_state_counts
        max_checks = opts[:max_checks_per_state]
        rollup_alerts_by_state.inject([]) do |memo, (alert_state, rollup_alerts)|
          alerts = (max_checks && max_checks > 0) ? rollup_alerts[0..(max_checks - 1)] : rollup_alerts
          next memo if alerts.empty?
          checks = alerts.collect {|alert| alert.check.name}
          checks << '...' if checks.length < state_counts[alert_state]
          memo << "#{alert_state.titleize}: #{checks.join(', ')}"
          memo
        end.join('; ')
      end

      def to_s
        contact = medium.contact
        msg = "Alert via #{medium.type}:#{medium.address} to contact #{contact.id} (#{contact.first_name} #{contact.last_name}): "
        msg += type_sentence_case
        if rollup
          msg += " - #{rollup_states_summary} (#{rollup_states_detail_text(:max_checks_per_state => 3)})"
        else
          msg += " - '#{self.check.name}'"
          unless ['acknowledgement', 'test'].include?(type)
            msg += " is #{state_title_case}"
          end
          if ['acknowledgement'].include?(type)
            msg += " has been acknowledged, unscheduled maintenance created for "
            msg += time_period_in_words(acknowledgement_duration)
          end
          if summary && summary.length > 0
            msg += " - #{summary}"
          end
        end
      end

      # def record_send_success!
      #   @logger.info "Sent alert successfully: #{to_s}"
      # end

      # TODO: perhaps move message send failure porting to this method
      # to avoid duplication in the gateways, and to more easily allow
      # better error reporting on message generation / send failure
      #def record_send_failure!(opts)
      #  exception = opts[:exception]
      #  message   = opts[:message]
      #  @logger.error "Error sending an alert! #{alert}"
      #end

      private

      def rollup_alerts_by_state
        Flapjack::Data::RollupAlert.states.inject({}) do |memo, alert_state|
          memo[alert_state] = self.rollup_alerts.intersect(:state => alert_state).all
          memo
        end
      end

      def rollup_state_counts
        Flapjack::Data::RollupAlert.states.inject({}) do |memo, alert_state|
          memo[alert_state] = self.rollup_alerts.intersect(:state => alert_state).count
          memo
        end
      end

    end
  end
end
