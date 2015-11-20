#!/usr/bin/env ruby

require 'securerandom'

require 'swagger/blocks'

require 'flapjack/data/extensions/short_name'

module Flapjack
  module Data
    class Metrics

      extend ActiveModel::Naming

      include Swagger::Blocks

      include Flapjack::Data::Extensions::ShortName

      def total_keys
        Flapjack.redis.dbsize
      end

      def event_queue_length
        Flapjack.redis.llen('events')
      end

      def processed_events
        global_stats = Flapjack::Data::Statistic.
          intersect(:instance_name => 'global').all.first

        [:all_events, :ok_events, :failure_events, :action_events,
         :invalid_events].each_with_object({}) do |event_type, memo|

          memo[event_type] = global_stats.nil? ? 0 : global_stats.send(event_type)
        end
      end

      def check_freshness
        ages = [0, 60, 300, 900, 3600]

        start_time = Time.now

        current_checks = Flapjack::Data::Check.intersect(:enabled => true).all

        skeleton = {}
        ages.each {|a| skeleton[a] = 0 }
        age_ranges = ages.reverse.each_cons(2)

        current_checks.each_with_object(skeleton) do |check, memo|
          current_state = check.current_state
          last_update = current_state.nil? ? nil : current_state.updated_at
          next if last_update.nil?
          check_age = start_time - last_update
          check_age = 0 unless check_age > 0
          if check_age >= ages.last
            memo[ages.last] += 1
          else
            age_range = age_ranges.detect {|a, b| (check_age < a) && (check_age >= b) }
            memo[age_range.last] += 1 unless age_range.nil?
          end
        end
      end

      def check_counts
        {
          :all     => Flapjack::Data::Check.count,
          :enabled => Flapjack::Data::Check.intersect(:enabled => true).count,
          :failing => Flapjack::Data::Check.intersect(:failing => true).count
        }
      end

      swagger_schema :data_Metrics do
        key :required, [:data]
        property :data do
          key :"$ref", :Metrics
        end
        property :links do
          key :"$ref", :Links
        end
      end

      swagger_schema :Metrics do
        key :required, [:type, :total_keys,
          :event_queue_length, :processed_events,
          :check_freshness, :check_counts]
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Metrics.short_model_name.singular]
        end
        property :total_keys do
          key :type, :integer
          key :minimum, 0
        end
        property :event_queue_length do
          key :type, :integer
          key :minimum, 0
        end
        property :processed_events do
          key :"$ref", :MetricsProcessedEventCounts
        end
        property :check_freshness do
          key :"$ref", :MetricsCheckFreshnessCounts
        end
        property :check_counts do
          key :"$ref", :MetricsCheckCounts
        end
      end

      swagger_schema :MetricsProcessedEventCounts do
        key :required, [:all_events, :ok_events, :failure_events,
                        :action_events, :invalid_events]
        property :all_events do
          key :type, :integer
          key :minimum, 0
        end
        property :ok_events do
          key :type, :integer
          key :minimum, 0
        end
        property :failure_events do
          key :type, :integer
          key :minimum, 0
        end
        property :action_events do
          key :type, :integer
          key :minimum, 0
        end
        property :invalid_events do
          key :type, :integer
          key :minimum, 0
        end
      end

      swagger_schema :MetricsCheckFreshnessCounts do
        key :required, [:"0", :"60", :"300", :"900", :"3600"]
        property :"0" do
          key :type, :integer
          key :minimum, 0
        end
        property :"60" do
          key :type, :integer
          key :minimum, 0
        end
        property :"300" do
          key :type, :integer
          key :minimum, 0
        end
        property :"900" do
          key :type, :integer
          key :minimum, 0
        end
        property :"3600" do
          key :type, :integer
          key :minimum, 0
        end
      end

      swagger_schema :MetricsCheckCounts do
        key :required, [:all, :enabled, :failing]
        property :all do
          key :type, :integer
          key :minimum, 0
        end
        property :enabled do
          key :type, :integer
          key :minimum, 0
        end
        property :failing do
          key :type, :integer
          key :minimum, 0
        end
      end

      def self.swagger_included_classes
        # hack -- hardcoding for now
        []
      end

      def self.jsonapi_methods
        @jsonapi_methods ||= {
          :get => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:total_keys, :processed_events, :event_queue_length,
                            :check_freshness, :check_counts],
            :description => "Get global metrics and event counter values."
          )
        }
      end

      def self.jsonapi_associations
        @jsonapi_associations ||= {}
      end
    end
  end
end