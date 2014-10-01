#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/check'
require 'flapjack/data/event'
require 'flapjack/data/scheduled_maintenance'

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      module CheckMethods

        module Helpers

          def create_scheduled_maintenances(check_ids)
            sched_maint_params = wrapped_params('scheduled_maintenances')

            sched_maints = Flapjack::Data::Check.find_by_ids!(*check_ids).inject({}) do |memo, check|
              memo[check] = []
              sched_maint_params.collect do |wp|
                start_time = validate_and_parsetime(wp['start_time'])
                memo[check] << Flapjack::Data::ScheduledMaintenance.new(:start_time => start_time,
                  :end_time => start_time.nil? ? nil : (start_time + wp['duration'].to_i),
                  :summary => wp['summary'])
              end
              memo
            end

            errs = nil

            Flapjack::Data::Check.lock(Flapjack::Data::ScheduledMaintenance) do

              invalid_maint = nil

              sched_maints.detect do |check, maints|
                invalid_maint = maints.detect {|m| m.invalid? }
              end

              if invalid_maint
                errs = invalid_maint.errors.full_messages
              else
                sched_maints.each do |check, maints|
                  maints.each do |m|
                    m.save
                    check.add_scheduled_maintenance(m)
                  end
                end
              end
            end

            if errs
              halt err(403, "Scheduled maintenance validation failed, #{errs}")
            end

            status 204
          end

          def create_unscheduled_maintenances(check_ids)
            unsched_maint_params = wrapped_params('unscheduled_maintenances', false)
            checks = Flapjack::Data::Check.find_by_ids!(*check_ids)

            unsched_maints = unsched_maint_params.collect do |wp|
              dur = wp['duration'] ? wp['duration'].to_i : nil
              duration = (dur.nil? || (dur <= 0)) ? (4 * 60 * 60) : dur
              summary = wp['summary']

              opts = {:duration => duration}
              opts[:summary] = summary if summary

              Flapjack::Data::Event.create_acknowledgements(
                config['processor_queue'] || 'events', checks, opts)
            end

            status 204
          end

          def update_unscheduled_maintenances(check_ids)
            Flapjack::Data::Check.find_by_ids!(*check_ids).each do |check|
              apply_json_patch('unscheduled_maintenances') do |op, property, linked, value|
                case op
                when 'replace'
                  if ['end_time'].include?(property)
                    end_time = validate_and_parsetime(value)
                    check.clear_unscheduled_maintenance(end_time.to_i)
                  end
                end
              end
            end

            status 204
          end

          def delete_scheduled_maintenances(start_time, check_ids)
            Flapjack::Data::Check.find_by_ids!(*check_ids).each do |check|
              next unless sched_maint = check.scheduled_maintenances_by_start.
                intersect_range(start_time.to_i, start_time.to_i, :by_score => true).all.first
              check.end_scheduled_maintenance(sched_maint, Time.now)
            end
            status 204
          end

          def create_test_notifications(check_ids)
            test_notifications = wrapped_params('test_notifications', false)
            checks = Flapjack::Data::Check.find_by_ids!(*check_ids)

            test_notifications.each do |wp|
              summary = wp['summary'] ||
                        "Testing notifications to all contacts interested in #{checks.map(&:name).join(', ')}"
              Flapjack::Data::Event.test_notifications(
                config['processor_queue'] || 'events',
                checks, :summary => summary)
            end
            status 204
          end

        end

      end

    end

  end

end