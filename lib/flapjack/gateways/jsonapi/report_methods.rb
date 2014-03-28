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

          def load_api_data(entity_names, entity_check_names, result_type, &block)
            entities_by_name             = {}
            entity_checks_by_entity_name = {}

            unless entity_names.nil? || entity_names.empty?
              entity_names.each do |entity_name|
                entity = find_entity(entity_name)
                entities_by_name[entity_name] = entity
                check_list_names = entity.check_list
                entity_checks_by_entity_name[entity_name] = check_list_names.collect {|entity_check_name|
                  find_entity_check_by_name(entity_name, entity_check_name)
                }
              end
            end

            unless entity_check_names.nil? || entity_check_names.empty?
              entity_check_names.each do |entity_check_name|
                entity_name, check_name = entity_check_name.split(':', 2)
                entities_by_name[entity_name] ||= find_entity(entity_name)

                entity_checks_by_entity_name[entity_name] ||= []
                entity_checks_by_entity_name[entity_name] << find_entity_check_by_name(entity_name, check_name)
              end
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

          app.get %r{/reports/(status|outages|(?:un)?scheduled_maintenances|downtime)} do
            content_type JSONAPI_MEDIA_TYPE
            cors_headers

            action = params[:captures].first

            entity_names, entity_check_names = parse_entity_and_check_names

            args = []

            unless 'status'.eql?(action)
              args += [validate_and_parsetime(params[:start_time]),
                       validate_and_parsetime(params[:end_time])]
            end

            entity_data, check_data = load_api_data(entity_names, entity_check_names, action) {|presenter|
              presenter.send(action, *args)
            }

            '{"entities":' + entity_data.to_json +
              ',"linked":{"checks":' + check_data.to_json + '}}'
          end

        end

      end

    end

  end

end
