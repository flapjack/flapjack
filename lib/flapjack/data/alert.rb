#!/usr/bin/env ruby

require 'active_support/inflector'

require 'sandstorm/records/redis_record'

require 'flapjack/utility'

# Alert is the object ready to send to someone, complete with an address and all
# the data with which to render the text of the alert in the appropriate gateway

module Flapjack
  module Data
    class Alert

      include Flapjack::Utility
      include Sandstorm::Records::RedisRecord

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
                        :condition_duration => :integer,

                        :rollup        => :string,
                        :rollup_states_json => :string,

                        :event_hash    => :string

      belongs_to :medium, :class_name => 'Flapjack::Data::Medium', :inverse_of => :alerts
        # media_type, address, :rollup_threshold retrieved from medium
        # contact_id, name retrieved from medium.contact

      belongs_to :check, :class_name => 'Flapjack::Data::Check', :inverse_of => :alerts
        # entity, in_scheduled_maintenance, in_unscheduled_maintenance retrieved from check

      def self.states
        ['ok', 'critical', 'warning', 'unknown', 'test', 'acknowledgement']
      end

      validates :state, :presence => true, :inclusion => {:in => self.states },
        :unless => proc {|n| n.type == 'test'}
      validates :condition_duration, :presence => true,
        :numericality => {:minimum => 0}, :unless => proc {|n| n.type == 'test'}

      validates_each :rollup_states_json do |record, att, value|
        unless value.nil?
          states = JSON.parse(value)
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
        @rollup_states = JSON.parse(self.rollup_states_json)
      end

      def rollup_states=(rollup_states)
        @rollup_states = rollup_states
        self.rollup_states_json = rollup_states.nil? ? nil : Flapjack.dump_json(rollup_states)
      end

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
