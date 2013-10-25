#!/usr/bin/env ruby

require 'active_support/inflector'

# Alert is the object ready to send to someone, complete with an address and all
# the data with which to render the text of the alert in the appropriate gateway
#
# It should possibly be renamed AlertPresenter

module Flapjack
  module Data
    class Alert

      # from Flapjack::Data::Notification
      attr_reader :event_id,
                  :state,
                  :summary,
                  :acknowledgement_duration,
                  :last_state,
                  :last_summary,
                  :state_duration,
                  :details,
                  :time,
                  :notification_type,
                  :event_count,
                  :tags

      # from Flapjack::Data::Message
                # :id,
      attr_reader :media,
                  :address,
                  :rollup,
                  :contact_id,
                  :contact_first_name,
                  :contact_last_name

      # from Flapjack::Notifier
      attr_reader :rollup_threshold,
                  :rollup_alerts,
                  :in_scheduled_maintenance,
                  :in_unscheduled_maintenance

      # from self
      attr_reader :entity,
                  :check,
                  :notification_id

      def initialize(contents, opts)
        raise "no logger supplied" unless @logger = opts[:logger]

        @event_id                   = contents['event_id']
        @state                      = contents['state']
        @summary                    = contents['summary']
        @acknowledgement_duration   = contents['duration'] # SMELLY
        @last_state                 = contents['last_state']
        @last_summary               = contents['last_summary']
        @state_duration             = contents['state_duration']
        @details                    = contents['details']
        @time                       = contents['time']
        @notification_type          = contents['notification_type']
        @event_count                = contents['event_count']
        @tags                       = contents['tags']

        @media                      = contents['media']
        @address                    = contents['address']
        @rollup                     = contents['rollup']
        @contact_id                 = contents['contact_id']
        @contact_first_name         = contents['contact_first_name']
        @contact_last_name          = contents['contact_last_name']

        @rollup_threshold           = contents['rollup_threshold']
        @rollup_alerts              = contents['rollup_alerts']
        @in_scheduled_maintenance   = contents['in_scheduled_maintenance']
        @in_unscheduled_maintenance = contents['in_unscheduled_maintenance']

        @entity, @check             = @event_id.split(':', 2)
        @notification_id            = contents['id'] || SecureRandom.uuid

        allowed_states        = ['ok', 'critical', 'warning', 'unknown', 'test_notifications', 'acknowledgement']
        allowed_rollup_states = ['critical', 'warning', 'unknown']
        raise "state #{@state.inspect} is invalid" unless
          allowed_states.include?(@state)

        raise "state_duration #{@state_duration.inspect} is invalid" unless
          @state_duration && @state_duration.is_a?(Integer) && @state_duration >= 0

        if @rollup_alerts
          raise "rollup_alerts should be nil or a hash" unless @rollup_alerts.is_a?(Hash)
          @rollup_alerts.each_pair do |check, details|
            raise "duration of rollup_alerts['#{check}'] must be an integer" unless
              details['duration'] && details['duration'].is_a?(Integer)
            raise "state of rollup_alerts['#{check}'] is invalid" unless
              details['state'] && allowed_rollup_states.include?(details['state'])
          end
        end

      end

      def type
        case @rollup
        when "problem"
          "rollup_problem"
        when "recovery"
          "rollup_recovery"
        else
          @notification_type
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
        ['ok'].include?(@state) ? @state.upcase : @state.titleize
      end

      def last_state_title_case
        ['ok'].include?(@last_state) ? @last_state.upcase : @last_state.titleize
      end

      def rollup_alerts_by_state
        ['critical', 'warning', 'unknown'].inject({}) do |memo, state|
          alerts = rollup_alerts.find_all {|alert| alert[1]['state'] == state}
          memo[state] = alerts
          memo
        end
      end

      def rollup_state_counts
        rollup_alerts.inject({}) do |memo, alert|
          memo[alert[1]['state']] = (memo[alert[1]['state']] || 0) + 1
          memo
        end
      end

      def rollup_states_summary
        state_counts = rollup_state_counts
        ['critical', 'warning', 'unknown'].inject([]) do |memo, state|
          next memo unless rollup_state_counts[state]
          memo << "#{state.titleize}: #{state_counts[state]}"
          memo
        end.join(', ')
      end

      # produces a textual list of checks that are failing broken down by state, eg:
      # Critical: 'PING' on 'foo-app-01.example.com', 'SSH' on 'foo-app-01.example.com';
      #   Warning: 'Disk / Utilisation' on 'foo-app-02.example.com'
      def rollup_states_detail_text(opts)
        max_checks = opts[:max_checks_per_state]
        rollup_alerts_by_state.inject([]) do |memo, state|
          state_titleized = state[0].titleize
          alerts = max_checks && max_checks > 0 ? state[1][0..(max_checks - 1)] : state[1]
          next memo if alerts.empty?
          checks = alerts.map {|alert| alert[0]}
          checks << '...' if checks.length < rollup_state_counts[state[0]]
          memo << "#{state[0].titleize}: #{checks.join(', ')}"
          memo
        end.join('; ')
      end

    end
  end
end
