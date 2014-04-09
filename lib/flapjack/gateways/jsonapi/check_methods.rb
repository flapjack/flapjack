#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/event'

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      module CheckMethods

        module Helpers

          def bulk_jsonapi_check_action(entity_check_names, params = {}, &block)
            unless entity_check_names.nil? || entity_check_names.empty?
              entity_check_names.each do |entity_check_name|
                entity_name, check_name = entity_check_name.split(':', 2)
                entity = find_entity(entity_name)
                yield find_entity_check(entity, check_name)
              end
            end
          end

        end

        def self.registered(app)
          app.helpers Flapjack::Gateways::JSONAPI::Helpers
          app.helpers Flapjack::Gateways::JSONAPI::CheckMethods::Helpers

          # create a scheduled maintenance period for a check on an entity
          app.post %r{/checks/([^/]+)/scheduled_maintenances} do
            check_names = params[:captures][0].split(',')

            start_time = validate_and_parsetime(params[:start_time])
            halt( err(403, "start time must be provided") ) unless start_time

            bulk_jsonapi_check_action(check_names) do |entity_check|
              entity_check.create_scheduled_maintenance(start_time,
                params[:duration].to_i, :summary => params[:summary])
            end

            response.headers['Location'] =
              "#{request.base_url}/reports/scheduled_maintenances?" +
              "start_time=#{params[:start_time]}&" + check_names.collect {|cn|
                "check[]=#{cn}"
              }.join("&")

            status 201
          end

          # create an acknowledgement for a service on an entity
          # NB currently, this does not acknowledge a specific failure event, just
          # the entity-check as a whole
          app.post %r{checks/([^/]+)/unscheduled_maintenances} do
            check_names = params[:captures][0].split(',')

            dur = params[:duration] ? params[:duration].to_i : nil
            duration = (dur.nil? || (dur <= 0)) ? (4 * 60 * 60) : dur
            summary = params[:summary]

            opts = {'duration' => duration}
            opts['summary'] = summary if summary

            t = Time.now

            bulk_jsonapi_check_action(check_names) do |entity_check|
              Flapjack::Data::Event.create_acknowledgement(
                entity_check.entity_name, entity_check.check,
                :summary => params[:summary],
                :duration => duration,
                :redis => redis)
            end

            response.headers['Location'] =
              "#{request.base_url}/reports/unscheduled_maintenances?" +
              "start_time=#{t.iso8601}&" + check_names.collect {|cn|
                "check[]=#{cn}"
              }.join("&")

            status 201
          end

          app.delete %r{/checks/([^/]+)/((?:un)?scheduled_maintenances)} do
            check_names = params[:captures][0].split(',')
            action = params[:captures][1]

            act_proc = case action
            when 'scheduled_maintenances'
              start_time = validate_and_parsetime(params[:start_time])
              halt( err(403, "start time must be provided") ) unless start_time
              proc {|entity_check| entity_check.end_scheduled_maintenance(start_time.to_i) }
            when 'unscheduled_maintenances'
              end_time = validate_and_parsetime(params[:end_time]) || Time.now
              proc {|entity_check| entity_check.end_unscheduled_maintenance(end_time.to_i) }
            end

            bulk_jsonapi_check_action(check_names, &act_proc)
            status 204
          end

          app.post %r{/checks/([^/]+)/test_notifications} do
            check_names = params[:captures][0].split(',')

             bulk_jsonapi_check_action(check_names) do |entity_check|
              summary = params[:summary] ||
                        "Testing notifications to all contacts interested in entity #{entity_check.entity.name}"
              Flapjack::Data::Event.test_notifications(
                entity_check.entity_name, entity_check.check,
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
