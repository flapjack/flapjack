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
            check_names = params[:captures][0].split(',')

            start_time = validate_and_parsetime(params[:start_time])
            halt( err(403, "start time must be provided") ) unless start_time

            checks_for_check_names(check_names).each do |check|
              check.create_scheduled_maintenance(start_time,
                params[:duration].to_i, :summary => params[:summary])
            end

            response.headers['Location'] =
              "#{request.base_url}/scheduled_maintenance_report/checks/" +
                check_names.join(',') + "?start_time=#{params[:start_time]}"

            status 201
          end

          # create an acknowledgement for a service on an entity
          # NB currently, this does not acknowledge a specific failure event, just
          # the entity-check as a whole
          app.post %r{^/unscheduled_maintenances/checks/([^/]+)$} do
            check_names = params[:captures][0].split(',')

            dur = params[:duration] ? params[:duration].to_i : nil
            duration = (dur.nil? || (dur <= 0)) ? (4 * 60 * 60) : dur
            summary = params[:summary]

            opts = {'duration' => duration}
            opts['summary'] = summary if summary

            t = Time.now

            checks_for_check_names(check_names).each do |check|
              Flapjack::Data::Event.create_acknowledgement(
                check.entity_name, check.check,
                :summary => params[:summary],
                :duration => duration,
                :redis => redis)
            end

            response.headers['Location'] =
              "#{request.base_url}/unscheduled_maintenance_report/checks/" +
                check_names.join(',') + "?start_time=#{t.iso8601}&"

            status 201
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
            checks_for_check_names(params[:captures][0].split(',')).each do |check|
              summary = params[:summary] ||
                        "Testing notifications to all contacts interested in entity #{check.entity.name}"
              Flapjack::Data::Event.test_notifications(
                check.entity_name, check.check,
                :summary => summary,
                :redis => redis)
            end
            status 201
          end

        end

      end

    end

  end

end
