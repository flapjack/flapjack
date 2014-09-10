#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/gateways/jsonapi/check_methods_helpers'

# NB: documentation changes required, this now uses individual check ids rather
# than v1's 'entity_name:check_name' pseudo-id

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      module CheckMethods

        def self.registered(app)
          app.helpers Flapjack::Gateways::JSONAPI::Helpers
          app.helpers Flapjack::Gateways::JSONAPI::CheckMethods::Helpers

          app.get %r{^/checks(?:/)?(.+)?$} do
            requested_checks = if params[:captures] && params[:captures][0]
              params[:captures][0].split(',').uniq
            else
              nil
            end

            checks = if requested_checks
              Flapjack::Data::Check.find_by_ids!(*requested_checks)
            else
              Flapjack::Data::Check.all
            end

            if requested_checks && checks.empty?
              raise Flapjack::Gateways::JSONAPI::RecordsNotFound.new(Flapjack::Data::Check, requested_checks)
            end

            checks_json = checks.collect {|check| check.to_json}.join(",")

            '{"checks":[' + checks_json + ']}'
          end

          app.patch %r{^/checks/(.+)$} do
            requested_checks = params[:captures][0].split(',').uniq
            checks = Flapjack::Data::Check.find_by_ids!(*requested_checks)
            if checks.empty?
              raise Flapjack::Gateways::JSONAPI::RecordsNotFound.new(Flapjack::Data::Check, requested_checks)
            end

            checks.each do |check|
              apply_json_patch('checks') do |op, property, linked, value|
                case op
                when 'replace'
                  if ['enabled'].include?(property)
                    # explicitly checking for false being passed in
                    check.disable! if value.is_a?(FalseClass)
                  end
                end
              end
            end

            status 204
          end

          app.post %r{^/scheduled_maintenances/checks/(.+)$} do
            create_scheduled_maintenances(params[:captures][0].split(','))
          end

          # NB this does not acknowledge a specific failure event, just
          # the check as a whole
          app.post %r{^/unscheduled_maintenances/checks/(.+)$} do
            create_unscheduled_maintenances(params[:captures][0].split(','))
          end

          app.patch %r{^/unscheduled_maintenances/checks/(.+)$} do
            update_unscheduled_maintenances(params[:captures][0].split(','))
          end

          app.delete %r{^/scheduled_maintenances/checks/(.+)$} do
            start_time = validate_and_parsetime(params[:start_time])
            halt( err(403, "start time must be provided") ) unless start_time

            delete_scheduled_maintenances(start_time, params[:captures][0].split(','))
          end

          app.post %r{^/test_notifications/checks/(.+)$} do
            create_test_notifications(params[:captures][0].split(','))
          end

        end

      end

    end

  end

end
