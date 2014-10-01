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

          app.post '/checks' do
            checks_data = wrapped_params('checks')

            check_err = nil
            check_ids = nil
            checks    = nil

           data_ids = checks_data.reject {|c| c['id'].nil? }.
              map {|co| co['id'].to_s }

            Flapjack::Data::Check.lock do

              conflicted_ids = data_ids.select {|id|
                Flapjack::Data::Check.exists?(id)
              }

              if conflicted_ids.length > 0
                check_err = "Checks already exist with the following ids: " +
                              conflicted_ids.join(', ')
              else
                checks = checks_data.collect do |cd|
                  Flapjack::Data::Check.new(:id => cd['id'], :name => cd['name'],
                    :enabled => cd['enabled'])
                end
              end

              if invalid = checks.detect {|c| c.invalid? }
                check_err = "Check validation failed, " + invalid.errors.full_messages.join(', ')
              else
                check_ids = checks.collect {|c| c.save; c.id }
              end

            end

            if check_err
              halt err(403, check_err)
            end

            status 201
            response.headers['Location'] = "#{base_url}/checks/#{check_ids.join(',')}"
            Flapjack.dump_json(check_ids)
          end

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

            Flapjack.dump_json(:checks => checks)
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
                    case value
                    when TrueClass
                      check.enabled = true
                      check.save
                    when FalseClass
                      check.enabled = false
                      check.save
                    end
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
