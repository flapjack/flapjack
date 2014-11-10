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
            checks_data, unwrap = wrapped_params('checks')

            check_err = nil
            checks    = nil

            data_ids = checks_data.reject {|c| c['id'].nil? }.
              map {|co| co['id'].to_s }

            Flapjack::Data::Check.lock do
              conflicted = Flapjack::Data::Check.find_by_ids(data_ids)

              if conflicted.empty?
                checks = checks_data.collect do |cd|
                  Flapjack::Data::Check.new(:id => cd['id'], :name => cd['name'],
                    :initial_failure_delay => cd['initial_failure_delay'],
                    :repeat_failure_delay  => cd['repeat_failure_delay'],
                    :enabled => cd['enabled'])
                end

                if invalid = checks.detect {|c| c.invalid? }
                  check_err = "Check validation failed, " + invalid.errors.full_messages.join(', ')
                else
                  checks.each {|c| c.save }
                end
              else
                check_err = "Checks already exist with the following ids: " +
                              conflicted_ids.join(', ')
              end
            end

            halt err(403, check_err) unless check_err.nil?

            status 201
            response.headers['Location'] = "#{base_url}/checks/#{checks.map(&:id).join(',')}"
            checks_as_json = Flapjack::Data::Check.as_jsonapi(unwrap, *checks)
            Flapjack.dump_json(:checks => checks_as_json)
          end

          app.get %r{^/checks(?:/)?(.+)?$} do
            requested_checks = if params[:captures] && params[:captures][0]
              params[:captures][0].split(',').uniq
            else
              nil
            end

            unwrap = !requested_checks.nil? && (requested_checks.size == 1)

            checks, meta = if requested_checks
              requested = Flapjack::Data::Check.find_by_ids!(*requested_checks)

              if requested.empty?
                raise Flapjack::Gateways::JSONAPI::RecordsNotFound.new(Flapjack::Data::Check, requested_checks)
              end

              [requested, {}]
            else
              paginate_get(Flapjack::Data::Check.sort(:name, :order => 'alpha'),
                :total => Flapjack::Data::Check.count, :page => params[:page],
                :per_page => params[:per_page])
            end

            checks_as_json = Flapjack::Data::Check.as_jsonapi(unwrap, *checks)
            Flapjack.dump_json({:checks => checks_as_json}.merge(meta))
          end

          app.put %r{^/checks/(.+)$} do
            requested_checks = params[:captures][0].split(',').uniq
            checks = Flapjack::Data::Check.find_by_ids!(*requested_checks)
            if checks.empty?
              raise Flapjack::Gateways::JSONAPI::RecordsNotFound.new(Flapjack::Data::Check, requested_checks)
            end

            checks_data, unwrap = wrapped_params('checks')

            if checks_data.map {|cd| cd['id'] }.sort != requested_checks.sort
              halt err(403, "Id mismatch updating checks")
            end

            changed = checks_data.collect do |cd|
              check = checks.detect {|c| c.id == cd['id']}
              cd.each_pair do |att, value|
                case att
                when 'enabled', 'name', 'initial_failure_delay', 'repeat_failure_delay'
                  check.send("#{att}=".to_sym, value)
                end
              end
              check
            end

            if invalid = changed.detect {|c| c.invalid? }
              halt err(403,  "Check validation failed, " + invalid.errors.full_messages.join(', '))
            end

            changed.each {|c| c.save }
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
