#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/event'

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      module CheckMethods

        module Helpers

          def checks_for_check_names(check_names)
            return if check_names.nil?
            entity_cache = {}
            check_names.inject([]) do |memo, check_name|
              entity_name, check = check_name.split(':', 2)
              entity = (entity_cache[entity_name] ||= find_entity(entity_name))
              memo << find_entity_check(entity, check)
              memo
            end
          end

        end

        def self.registered(app)
          app.helpers Flapjack::Gateways::JSONAPI::Helpers
          app.helpers Flapjack::Gateways::JSONAPI::CheckMethods::Helpers

          # create a scheduled maintenance period for a check on an entity
          app.post %r{^/scheduled_maintenances/checks/([^/]+)$} do
            scheduled_maintenances = wrapped_params('scheduled_maintenances')
            checks_for_check_names(params[:captures][0].split(',')).each do |check|
              scheduled_maintenances.each do |wp|
                start_time = validate_and_parsetime(wp['start_time'])
                halt( err(403, "start time must be provided") ) unless start_time

                check.create_scheduled_maintenance(start_time,
                  wp[:duration].to_i, :summary => wp[:summary])
              end
            end

            status 204
          end

          # create an acknowledgement for a service on an entity
          # NB currently, this does not acknowledge a specific failure event, just
          # the entity-check as a whole
          app.post %r{^/unscheduled_maintenances/checks/([^/]+)$} do
            unscheduled_maintenances = wrapped_params('unscheduled_maintenances', false)
            checks_for_check_names(params[:captures][0].split(',')).each do |check|
              unscheduled_maintenances.each do |wp|
                dur = wp['duration'] ? wp['duration'].to_i : nil
                duration = (dur.nil? || (dur <= 0)) ? (4 * 60 * 60) : dur
                summary = wp['summary']

                opts = {:duration => duration}
                opts[:summary] = summary if summary

                Flapjack::Data::Event.create_acknowledgement(
                  check.entity_name, check.check, {:redis => redis}.merge(opts))
              end
            end

            status 204
          end

          app.patch %r{^/unscheduled_maintenances/checks/([^/]+)$} do
            checks_for_check_names(params[:captures][0].split(',')).each do |check|
              apply_json_patch('unscheduled_maintenances') do |op, property, linked, value|
                case op
                when 'replace'
                  if ['end_time'].include?(property)
                    end_time = validate_and_parsetime(value)
                    check.end_unscheduled_maintenance(end_time.to_i)
                  end
                end
              end
            end
            status 204
          end

          app.delete %r{^/scheduled_maintenances/checks/([^/]+)$} do
            start_time = validate_and_parsetime(params[:start_time])
            halt( err(403, "start time must be provided") ) unless start_time

            checks_for_check_names(params[:captures][0].split(',')).each do |check|
              check.end_scheduled_maintenance(start_time.to_i)
            end
            status 204
          end

          app.post %r{^/test_notifications/checks/([^/]+)$} do
            test_notifications = wrapped_params('test_notifications', false)
            checks_for_check_names(params[:captures][0].split(',')).each do |check|
              test_notifications.each do |wp|
                summary = wp['summary'] ||
                          "Testing notifications to all contacts interested in entity #{check.entity.name}"
                Flapjack::Data::Event.test_notifications(
                  check.entity_name, check.check,
                  :summary => summary,
                  :redis => redis)
              end
            end
            status 204
          end

        end

      end

    end

  end

end
