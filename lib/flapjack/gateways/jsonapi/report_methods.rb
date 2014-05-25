#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/entity'
require 'flapjack/data/check'

require 'flapjack/gateways/jsonapi/check_presenter'

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      module ReportMethods

        module Helpers

          def load_api_data(entity_ids, check_ids, &block)
            entities = if entity_ids.nil?
              Flapjack::Data::Entity.all
            elsif !entity_ids.empty?
              Flapjack::Data::Entity.find_by_ids!(entity_ids)
            else
              []
            end

            checks = if check_ids.nil?
              Flapjack::Data::Check.all
            elsif !check_ids.empty?
              Flapjack::Data::Check.find_by_ids!(check_ids)
            else
              []
            end

            extra_entities = checks.map(&:entity)
            extra_checks   = entities.map(&:checks).map(&:all).flatten(1)

            all_entities = (entities + extra_entities).uniq {|e| e.id}

            linked_checks_ids = all_entities.empty? ? {} :
              Flapjack::Data::Entity.associated_ids_for_checks(all_entities.map(&:id))

            entity_data = all_entities.collect {|entity|
              entity.as_json(:checks_ids => linked_checks_ids[entity.id])
            }

            report_data = []
            check_data = []

            all_checks = (checks + extra_checks).uniq {|c| c.id}

            linked_entity_ids = all_checks.empty? ? {} :
              Flapjack::Data::Check.associated_ids_for_entity(all_checks.map(&:id))

            all_checks.each do |check|
              entity_id = linked_entity_ids[check.id]
              report_data << yield(Flapjack::Gateways::JSONAPI::CheckPresenter.new(check)).
                merge('links'  => {
                  'entity' => [entity_id],
                  'check'  => [check.id],
                })

              check_data << check.as_json(:entity_id => entity_id)
            end

            [report_data, entity_data, check_data]
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
              start_time = validate_and_parsetime(params[:start_time])
              start_time = start_time.to_i unless start_time.nil?
              end_time = validate_and_parsetime(params[:end_time])
              end_time = end_time.to_i unless end_time.nil?
              args += [start_time, end_time]
            end

            report_data, entity_data, check_data = case entities_or_checks
            when 'entities'
              entity_ids = params[:captures][2].nil? ? nil : params[:captures][2].split(',')
              load_api_data(entity_ids, []) {|presenter|
                presenter.send(action, *args.map)
              }
            when 'checks'
              check_ids = params[:captures][2].nil? ? nil : params[:captures][2].split(',')
              load_api_data([], check_ids) {|presenter|
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
