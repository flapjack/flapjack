#!/usr/bin/env ruby

require 'active_support/inflector'

require 'zermelo/records/redis'

require 'flapjack/utility'

require 'flapjack/data/condition'
require 'flapjack/data/state'

# Alert is the object ready to send to someone, complete with an address and all
# the data with which to render the text of the alert in the appropriate gateway

module Flapjack
  module Data
    class Alert

      include Flapjack::Utility
      include Zermelo::Records::RedisSet

      define_attributes :condition      => :string,
                        :action         => :string,
                        :summary        => :string,
                        :details        => :string,
                        :last_condition => :string,
                        :last_action    => :string,
                        :last_summary   => :string,
                        :event_count    => :integer,
                        :time           => :timestamp,
                        :acknowledgement_duration => :integer, # passed in as duration in other code
                        :condition_duration       => :float,
                        :rollup         => :string,
                        :rollup_states_json       => :string,
                        :event_hash     => :string

      belongs_to :medium, :class_name => 'Flapjack::Data::Medium', :inverse_of => :alerts

      belongs_to :check, :class_name => 'Flapjack::Data::Check', :inverse_of => :alerts

      validates :condition, :unless => proc {|s| !s.action.nil? },
        :inclusion => { :in => Flapjack::Data::Condition.healthy.keys +
                               Flapjack::Data::Condition.unhealthy.keys }

      validates :action, :allow_nil => true, :inclusion => {:in => Flapjack::Data::State::ACTIONS}

      validates :condition_duration, :presence => true, :allow_nil => true,
        :numericality => {:minimum => 0}, :unless => proc {|n| n.type == 'test'}

      validates_each :rollup_states_json do |record, att, value|
        unless value.nil?
          states = Flapjack.load_json(value)
          case states
          when Hash
            record.errors.add(att, 'must contain a serialized Hash (String => Array[String])') unless states.all? {|k,v|
              k.is_a?(String) && v.is_a?(Array) && v.all?{|vs| vs.is_a?(String)}
            }
          else
            record.errors.add(att, 'must contain a serialized Hash (String => Array[String])')
          end
        end
      end

      # TODO handle JSON exception
      def rollup_states
        if self.rollup_states_json.nil?
          @rollup_states = nil
          return
        end
        @rollup_states = Flapjack.load_json(self.rollup_states_json)
      end

      def rollup_states=(rollup_states)
        @rollup_states = rollup_states
        self.rollup_states_json = rollup_states.nil? ? nil : Flapjack.dump_json(rollup_states)
      end

      def notification_type
        self.class.notification_type(action, condition)
      end

      def self.notification_type(act, cond)
        case act
        when 'acknowledgement'
          'acknowledgement'
        when /\Atest_notifications(?:\s+#{Flapjack::Data::Condition.unhealthy.keys.join('|')})?\z/
          'test'
        when nil
          case cond
          when 'ok'
            'recovery'
          when 'warning', 'critical', 'unknown'
            'problem'
          else
            'unknown'
          end
        end
      end

      def type
        case self.rollup
        when "problem"
          "rollup_problem"
        when "recovery"
          "rollup_recovery"
        else
          notification_type
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

      def state
        @state ||= (self.action || self.condition)
      end

      def last_state
        @last_state ||= (self.last_action || self.last_condition)
      end

      def state_title_case
        ['ok'].include?(state) ? state.upcase : state.titleize
      end

      def last_state_title_case
        ['ok'].include?(last_state) ? last_state.upcase : last_state.titleize
      end

      def rollup_states_summary
        return '' if rollup_states.nil?
        rollup_states.each_with_object([]) do |(alert_state, alerts), memo|
          memo << "#{alert_state.titleize}: #{alerts.size}"
        end.join(', ')
      end

      # produces a textual list of checks that are failing broken down by state, eg:
      # Critical: 'PING' on 'foo-app-01.example.com', 'SSH' on 'foo-app-01.example.com';
      #   Warning: 'Disk / Utilisation' on 'foo-app-02.example.com'
      def rollup_states_detail_text(opts = {})
        return '' if rollup_states.nil?
        max_checks = opts[:max_checks_per_state]
        rollup_states.each_with_object([]) do |(alert_state, alerts), memo|
          alerts = alerts[0..(max_checks - 1)] unless max_checks.nil? || (max_checks <= 0)
          next if alerts.empty?
          alerts << '...' if alerts.size < rollup_states[alert_state].size
          memo << "#{alert_state.titleize}: #{alerts.join(', ')}"
        end.join('; ')
      end

      def to_s
        contact = medium.contact
        msg = "Alert via #{medium.transport}:#{medium.address} to contact #{contact.id} (#{contact.name}): "
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
    end
  end
end
