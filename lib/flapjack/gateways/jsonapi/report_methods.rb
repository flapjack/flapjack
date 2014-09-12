#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/entity'
require 'flapjack/data/entity_check'

require 'flapjack/gateways/jsonapi/check_presenter'

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      module ReportMethods

        module Helpers

          def load_api_data(entity_ids, event_ids, &block)
            entities = if entity_ids.nil?
              Flapjack::Data::Entity.all(:redis => redis)
            elsif !entity_ids.empty?
              entity_ids.collect {|entity_id| find_entity_by_id(entity_id) }
            else
              nil
            end

            checks = if event_ids.nil?
              Flapjack::Data::EntityCheck.find_current_names(:redis => redis).collect {|check_name|
                find_entity_check_by_name(*check_name.split(':', 2))
              }
            elsif !event_ids.empty?
              event_ids.collect {|event_id| find_entity_check_by_name(*event_id.split(':', 2)) }
            else
              nil
            end

            entities_by_id             = {}
            entity_checks_by_entity_id = {}

            (entities || []).each do |entity|
              entities_by_id[entity.id] = entity
              entity_checks_by_entity_id[entity.id] = entity.check_list.collect {|check_name|
                find_entity_check(entity, check_name)
              }
            end

            (checks || []).each do |check|
              check_entity = check.entity
              check_entity_id = check_entity.id
              entities_by_id[check_entity_id] ||= check_entity

              entity_checks_by_entity_id[check_entity_id] ||= []
              entity_checks_by_entity_id[check_entity_id] << check
            end

            entity_data = entities_by_id.inject([]) do |memo, (entity_id, entity)|
              entity_name = entity.name
              memo << {
                'id'    => entity_id,
                'name'  => entity_name,
                'links' => {
                  'checks' => entity_checks_by_entity_id[entity_id].collect {|entity_check|
                    "#{entity_name}:#{entity_check.check}"
                  },
                }
              }
              memo
            end

            report_data = []
            entity_check_data = []

            entity_checks_by_entity_id.each_pair do |entity_id, entity_checks|
              entity = entities_by_id[entity_id]
              entity_checks.each do |entity_check|
                entity_check_name = entity_check.check
                entity_check_id = "#{entity.name}:#{entity_check.check}"
                report_data << yield(Flapjack::Gateways::JSONAPI::CheckPresenter.new(entity_check)).
                    merge('links'  => {
                      'entity' => [entity_id],
                      'check'  => [entity_check_id],
                    })
                 entity_check_data << {
                  'id'        => entity_check_id,
                  'name'      => entity_check_name
                }
              end
            end

            [report_data, entity_data, entity_check_data]
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

            report_data, entity_data, check_data = case entities_or_checks
            when 'entities'
              entity_ids = params[:captures][2].nil? ? nil : params[:captures][2].split(',')
              load_api_data(entity_ids, []) {|presenter|
                presenter.send(action, *args)
              }
            when 'checks'
              entity_check_names = params[:captures][2].nil? ? nil : params[:captures][2].split(',')
              load_api_data([], entity_check_names) {|presenter|
                presenter.send(action, *args)
              }
            end

            "{\"#{action}_reports\":" + report_data.to_json + "," +
             "\"linked\":{\"entities\":" + entity_data.to_json + "," +
                         "\"checks\":" + check_data.to_json + "}}"
          end

        end

      end

    end

  end

end
