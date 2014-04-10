#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/entity'
require 'flapjack/data/entity_check'

require 'flapjack/gateways/jsonapi/entity_check_presenter'

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      module ReportMethods

        module Helpers

          def load_api_data(entity_ids, event_ids, action, &block)
            result_type = case action
            when 'status'
              'statuses'
            when 'outage'
              'outages'
            when 'scheduled_maintenance'
              'scheduled_maintenances'
            when 'unscheduled_maintenance'
              'unscheduled_maintenances'
            when 'downtime'
              'downtimes'
            end

            entities = if entity_ids.nil?
              Flapjack::Data::Entity.all(:redis => redis)
            elsif !entity_ids.empty?
              entity_ids.collect {|entity_id| find_entity_by_id(entity_id) }
            else
              nil
            end

            checks = if event_ids.nil?
              Flapjack::Data::EntityCheck.all(:redis => redis)
            elsif !event_ids.empty?
              event_ids.collect {|event_id| find_entity_check_by_name(*event_id.split(':', 2)) }
            else
              nil
            end

            entities_by_name             = {}
            entity_checks_by_entity_name = {}

            (entities || []).each do |entity|
              entities_by_name[entity.name] = entity
              check_list_names = entity.check_list
              entity_checks_by_entity_name[entity.name] = check_list_names.collect {|check_name|
                find_entity_check_by_name(entity.name, check_name)
              }
            end

            (checks || []).each do |check|
              check_entity = check.entity
              check_entity_name = check_entity.name
              entities_by_name[check_entity_name] ||= check_entity

              entity_checks_by_entity_name[check_entity_name] ||= []
              entity_checks_by_entity_name[check_entity_name] << check
            end

            entity_data = entities_by_name.inject([]) do |memo, (entity_name, entity)|
              memo << {
                'id'    => entity.id,
                'name'  => entity_name,
                'links' => {
                  'checks' => entity_checks_by_entity_name[entity_name].collect {|entity_check|
                    "#{entity_name}:#{entity_check.name}"
                  },
                }
              }
              memo
            end

            entity_check_data = entity_checks_by_entity_name.inject([]) do |memo, (entity_name, entity_checks)|
              memo += entity_checks.collect do |entity_check|
                entity_check_name = entity_check.name
                {
                  'id'        => "#{entity_name}:#{entity_check_name}",
                  'name'      => entity_check_name,
                  result_type => yield(Flapjack::Gateways::JSONAPI::EntityCheckPresenter.new(entity_check))
                }
              end
              memo
            end

            [entity_data, entity_check_data]
          end

        end

        def self.registered(app)
          app.helpers Flapjack::Gateways::JSONAPI::Helpers
          app.helpers Flapjack::Gateways::JSONAPI::ReportMethods::Helpers

          app.get %r{^/(status|outage|(?:un)?scheduled_maintenance|downtime)_report/(entities|checks)(?:/([^/]+))?$} do
            entities_or_checks = params[:captures][1]
            action = params[:captures][0]

            args = []
            unless 'status'.eql?(action)
              args += [validate_and_parsetime(params[:start_time]),
                       validate_and_parsetime(params[:end_time])]
            end

            entity_data, check_data = case entities_or_checks
            when 'entities'
              entity_ids = params[:captures][2].nil? ? nil : params[:captures][2].split(',')
              load_api_data(entity_ids, [], action) {|presenter|
                presenter.send(action, *args)
              }
            when 'checks'
              entity_check_names = params[:captures][2].nil? ? nil : params[:captures][2].split(',')
              load_api_data([], entity_check_names, action) {|presenter|
                presenter.send(action, *args)
              }
            end

            "{\"#{action}_reports\":" + entity_data.to_json +
              ",\"linked\":{\"checks\":" + check_data.to_json + "}}"
          end

        end

      end

    end

  end

end
