#!/usr/bin/env ruby

require 'securerandom'

require 'swagger/blocks'

module Flapjack
  module Data
    class Report

      include Swagger::Blocks

      class Outage
        attr_accessor :condition, :start_time, :end_time,
                      :duration, :summary, :details
      end

      def self.outage(check, options = {})
        start_time = options[:start_time]
        end_time   = options[:end_time]
        state_range = Zermelo::Filters::IndexRange.new(start_time, end_time, :by_score => true)

        hist_states = check.states.intersect(:created_at => state_range).all
        return [{:outage => []}, {}] if hist_states.empty?

        unless start_time.nil?
          first_and_prior_range = Zermelo::Filters::IndexRange.new(nil, start_time, :by_score => true)
          first_and_prior = check.states.
            intersect(:created_at => first_and_prior_range).
            offset(0, :limit => 2).all
          hist_states.unshift(first_and_prior.first) if first_and_prior.size == 2
        end

        # TODO the following works, but isn't the neatest
        num_states = hist_states.size

        index = 0
        result = []
        obj = nil

        while index < num_states do
          last_obj = obj
          obj = hist_states[index]
          index += 1

          next if Flapjack::Data::Condition.healthy?(obj.condition)

          if last_obj && (last_obj.condition == obj.condition)
            # TODO maybe build up arrays of these instead, and leave calling
            # classes to join them together if needed?
            result.last.summary << " / #{obj.summary}" if obj.summary
            result.last.details << " / #{obj.details}" if obj.details
            next
          end

          ts = obj.created_at

          next_ts_obj = hist_states[index..-1].detect {|hs| hs.condition != obj.condition }
          obj_et  = next_ts_obj ? next_ts_obj.created_at : end_time

          outage = Outage.new
          outage.condition  = obj.condition
          outage.start_time = (last_obj || !start_time) ? ts : [ts, start_time].max
          outage.end_time   = obj_et
          outage.duration   = obj_et ? (obj_et - outage.start_time) : nil
          outage.summary    = obj.summary || ''
          outage.details    = obj.details || ''

          result << outage
        end

        [{:outage => result},
         {}]
      end

      # TODO test whether the below overlapping logic is prone to off-by-one
      # errors; the numbers may line up more neatly if we consider outages to
      # start one second after the maintenance period ends.
      #
      # TODO test performance with larger data sets
      def self.downtime(check, options = {})
        start_time = options[:start_time]
        end_time   = options[:end_time]

        outs = outage(check, :start_time => start_time, :end_time => end_time).first[:outage]

        total_secs  = {}
        percentages = {}

        outs.collect {|obj| obj.condition}.uniq.each do |st|
          total_secs[st]  = 0
          percentages[st] = (start_time.nil? || end_time.nil?) ? nil : 0
        end

        unless outs.empty?

          # Initially we need to check for cases where a scheduled
          # maintenance period is fully covered by an outage period.
          # We then create two new outage periods to cover the time around
          # the scheduled maintenance period, and remove the original.

          delete_outs = []

          start_range  = Zermelo::Filters::IndexRange.new(nil, end_time, :by_score => true)
          finish_range = Zermelo::Filters::IndexRange.new(start_time, end_time, :by_score => true)
          sched_maintenances = check.scheduled_maintenances.
            intersect(:start_time => start_range, :end_time => finish_range).all

          sched_maintenances.each do |sm|

            split_outs = []

            outs.each { |o|
              next unless o.end_time && (o.start_time < sm.start_time) &&
                (o.end_time > sm.end_time)
              delete_outs << o

              out_split_start = Outage.new
              out_split_start.condition  = o.condition
              out_split_start.start_time = o.start_time
              out_split_start.end_time   = sm.start_time
              out_split_start.duration   = sm.start_time - o.start_time
              out_split_start.summary    = "#{o.summary} [split start]"

              out_split_end   = Outage.new
              out_split_end.condition    = o.condition
              out_split_end.start_time   = sm.end_time
              out_split_end.end_time     = o.end_time
              out_split_end.duration     = o.end_time - sm.end_time
              out_split_end.summary      = "#{o.summary} [split finish]"

              split_outs += [out_split_start, out_split_end]
            }

            outs -= delete_outs
            outs += split_outs
            # not strictly necessary to keep the data sorted, but
            # will make more sense when debgging
            outs.sort! {|a,b| a.start_time <=> b.start_time}
          end

          delete_outs.clear

          sched_maintenances.each do |sm|

            outs.each do |o|
              next unless o.end_time && (sm.start_time < o.end_time) &&
                (sm.end_time > o.start_time)

              if sm.start_time <= o.start_time &&
                sm.end_time >= o.end_time

                # outage is fully overlapped by the scheduled maintenance
                delete_outs << o

              elsif sm.start_time <= o.start_time
                # partially overlapping on the earlier side
                o.start_time = sm.end_time
                o.duration   = o.end_time - o.start_time
              elsif sm.end_time >= o.end_time
                # partially overlapping on the later side
                o.end_time   = sm.start_time
                o.duration   = o.end_time - o.start_time
              end
            end

            outs -= delete_outs
          end

          total_secs = outs.inject(total_secs) {|ret, o|
            ret[o.condition] += o.duration if o.duration
            ret
          }

          unless (start_time.nil? || end_time.nil?)
            total_secs.each_pair do |st, ts|
              percentages[st] = (total_secs[st] * 100.0) / (end_time.to_f - start_time.to_f)
            end
            total_secs['ok'] = (end_time - start_time) - total_secs.values.reduce(:+)
            percentages['ok'] = 100 - percentages.values.reduce(:+)
          end
        end

        [{:downtime => outs},
         {:total_seconds => total_secs, :percentages => percentages}]
      end


      def self.jsonapi_type
        self.name.demodulize.underscore
      end

      swagger_schema :Report do
        # FIXME
      end

      def self.jsonapi_methods
        [:get]
      end

      def self.jsonapi_attributes
        {
          :get => []
        }
      end

      def self.jsonapi_extra_locks
        {
          :get    => [],
        }
      end

      # read-only by definition; singular & multiple hashes of
      # method_name => [other classes to lock]
      def self.jsonapi_linked_methods
        {
          :singular => {
          },
          :multiple => {
          }
        }
      end

      def self.jsonapi_associations
        {
          :read_only => {
            :singular => [],
            :multiple => []
          }
        }
      end
    end
  end
end
