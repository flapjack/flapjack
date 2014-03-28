#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/entity'
require 'flapjack/data/entity_check'

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      module EntityMethods

        module Helpers

          def bulk_api_check_action(entity_names, entity_check_names, action, params = {})
            unless entity_names.nil? || entity_names.empty?
              entity_names.each do |entity_name|
                entity = find_entity(entity_name)
                check_names = entity.check_list.sort
                check_names.each do |check_name|
                  action.call( find_entity_check(entity, check_name) )
                end
              end
            end

            unless entity_check_names.nil? || entity_check_names.empty?
              entity_check_names.each do |entity_check_name|
                entity_name, check_name = entity_check_name.split(':', 2)
                entity = find_entity(entity_name)
                action.call( find_entity_check(entity, check_name) )
              end
            end
          end

        end

        def self.registered(app)
          app.helpers Flapjack::Gateways::JSONAPI::Helpers
          app.helpers Flapjack::Gateways::JSONAPI::EntityMethods::Helpers

          # Returns all (/entities) or some (/entities/A,B,C) or one (/entities/A) contact(s)
          # NB: only works with good data -- i.e. entity must have an id
          app.get %r{/entities(?:/)?([^/]+)?$} do
            content_type JSONAPI_MEDIA_TYPE
            cors_headers

            requested_entities = if params[:captures] && params[:captures][0]
              params[:captures][0].split(',').uniq
            else
              nil
            end

            entities = if requested_entities
              # TODO find by names
              Flapjack::Data::Entity.find_by_ids(requested_entities, :logger => logger, :redis => redis)
            else
              Flapjack::Data::Entity.all(:redis => redis)
            end
            entities.compact!

            if requested_entities && requested_entities.empty?
              raise Flapjack::Gateways::JSONAPI::EntitiesNotFound.new(requested_entities)
            end

            linked_contact_data, linked_contact_ids = if entities.empty?
              [[], []]
            else
              Flapjack::Data::Entity.contacts_jsonapi(entities.map(&:id), :redis => redis)
            end

            # can maybe send back linked checks in Flapjack 2.0

            entities_json = entities.collect {|entity|
              entity.linked_contact_ids = linked_contact_ids[entity.id]
              entity.to_jsonapi
            }.join(", ")

            '{"entities":[' + entities_json + ']' +
                ',"linked":{"contacts":' + linked_contact_data.to_json + '}}'
          end

          app.post '/entities' do
            pass unless is_json_request?

            content_type 'application/json'
            cors_headers

            entities = params[:entities]
            unless entities
              logger.debug("no entities object found in the following supplied JSON:")
              logger.debug(request.body)
              return err(403, "No entities object received")
            end
            return err(403, "The received entities object is not an Enumerable") unless entities.is_a?(Enumerable)
            return err(403, "Entity with a nil id detected") if entities.any? {|e| e['id'].nil?}

            entity_ids = entities.collect{|entity_data|
              Flapjack::Data::Entity.add(entity_data, :redis => redis)
              entity_data['id']
            }

            response.headers['Location'] = "#{request.base_url}/entities/#{entity_ids.join(',')}"
            status 201
            entity_ids.to_json
          end

          # create a scheduled maintenance period for a check on an entity
          app.post '/scheduled_maintenances' do
            cors_headers

            entity_names, check_names = parse_entity_and_check_names

            start_time = validate_and_parsetime(params[:start_time])
            halt( err(403, "start time must be provided") ) unless start_time

            act_proc = proc {|entity_check|
              entity_check.create_scheduled_maintenance(start_time,
                params[:duration].to_i, :summary => params[:summary])
            }

            bulk_api_check_action(entity_names, check_names, act_proc)

            response.headers['Location'] =
              "#{request.base_url}/reports/scheduled_maintenances?" +
              "start_time=#{params[:start_time]}" + (entity_names.nil? ? '' :
              ("&" + entity_names.collect{|en|
                "entity[]=#{en}"
              }.join("&"))) + (check_names.nil? ? '' :
              ("&" + check_names.collect {|cn|
                "check[]=#{cn}"
              }.join("&")))

            status 201
          end

          # create an acknowledgement for a service on an entity
          # NB currently, this does not acknowledge a specific failure event, just
          # the entity-check as a whole
          app.post '/acknowledgements' do
            cors_headers

            entity_names, check_names = parse_entity_and_check_names

            dur = params[:duration] ? params[:duration].to_i : nil
            duration = (dur.nil? || (dur <= 0)) ? (4 * 60 * 60) : dur
            summary = params[:summary]

            opts = {'duration' => duration}
            opts['summary'] = summary if summary

            act_proc = proc {|entity_check|
              Flapjack::Data::Event.create_acknowledgement(
                entity_check.entity_name, entity_check.check,
                :summary => params[:summary],
                :duration => duration,
                :redis => redis)
            }

            t = Time.now

            bulk_api_check_action(entity_names, check_names, act_proc)

            response.headers['Location'] =
              "#{request.base_url}/reports/unscheduled_maintenances?" +
              "start_time=#{t.iso8601}" + (entity_names.nil? ? '' :
              ("&" + entity_names.collect{|en|
                "entity[]=#{en}"
              }.join("&"))) + (check_names.nil? ? '' :
              ("&" + check_names.collect {|cn|
                "check[]=#{cn}"
              }.join("&")))

            status 201
          end

          app.delete %r{/((?:un)?scheduled_maintenances)} do
            cors_headers

            action = params[:captures][0]

            entity_names, check_names = parse_entity_and_check_names

            act_proc = case action
            when 'scheduled_maintenances'
              start_time = validate_and_parsetime(params[:start_time])
              halt( err(403, "start time must be provided") ) unless start_time
              opts = {}
              proc {|entity_check| entity_check.end_scheduled_maintenance(start_time.to_i) }
            when 'unscheduled_maintenances'
              end_time = validate_and_parsetime(params[:end_time]) || Time.now
              proc {|entity_check| entity_check.end_unscheduled_maintenance(end_time.to_i) }
            end

            bulk_api_check_action(entity_names, check_names, act_proc)
            status 204
          end

          app.post '/test_notifications' do
            cors_headers

            entity_names, check_names = parse_entity_and_check_names

            act_proc = proc {|entity_check|
              summary = params[:summary] ||
                        "Testing notifications to all contacts interested in entity #{entity_check.entity.name}"
              Flapjack::Data::Event.test_notifications(
                entity_check.entity_name, entity_check.check,
                :summary => summary,
                :redis => redis)
            }

            bulk_api_check_action(entity_names, check_names, act_proc)
            status 201
          end

        end

      end

    end

  end

end
