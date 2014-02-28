#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/entity'
require 'flapjack/data/entity_check'

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      module EntityMethods

        module Helpers

          def find_entity(entity_name)
            entity = Flapjack::Data::Entity.find_by_name(entity_name, :redis => redis)
            raise Flapjack::Gateways::JSONAPI::EntityNotFound.new(entity_name) if entity.nil?
            entity
          end

          def find_entity_check(entity, check_name)
            entity_check = Flapjack::Data::EntityCheck.for_entity(entity,
              check_name, :redis => redis)
            raise Flapjack::Gateways::JSONAPI::EntityCheckNotFound.new(entity_name, check_name) if entity_check.nil?
            entity_check
          end

          def find_tags(tags)
            halt err(403, "no tags") if tags.nil? || tags.empty?
            tags
          end

          def entities_and_checks(entity_name, check)
            if entity_name
              # backwards-compatible, single entity or entity&check from route
              entities = check ? nil : [entity_name]
              checks   = check ? {entity_name => check} : nil
            else
              # new and improved bulk API queries
              entities = params[:entity]
              checks   = params[:check]
              entities = [entities] unless entities.nil? || entities.is_a?(Array)
              # TODO err if checks isn't a Hash (similar rules as in flapjack-diner)
            end
            [entities, checks]
          end

          def bulk_api_check_action(entities, entity_checks, action, params = {})
            unless entities.nil? || entities.empty?
              entities.each do |entity_name|
                entity = find_entity(entity_name)
                checks = entity.check_list.sort
                checks.each do |check|
                  action.call( find_entity_check(entity, check) )
                end
              end
            end

            unless entity_checks.nil? || entity_checks.empty?
              entity_checks.each_pair do |entity_name, checks|
                entity = find_entity(entity_name)
                checks = [checks] unless checks.is_a?(Array)
                checks.each do |check|
                  action.call( find_entity_check(entity, check) )
                end
              end
            end
          end

          # NB: casts to UTC before converting to a timestamp
          def validate_and_parsetime(value)
            return unless value
            Time.iso8601(value).getutc.to_i
          rescue ArgumentError => e
            logger.error "Couldn't parse time from '#{value}'"
            nil
          end

        end

        # used for backwards-compatible route matching below
        ENTITY_CHECK_FRAGMENT = '(?:/([a-zA-Z0-9][a-zA-Z0-9\.\-]*[a-zA-Z0-9])(?:/(.+))?)?'

        def self.registered(app)

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

            cors_headers

            errors = []
            ret = nil

            # FIXME should scan for invalid records before making any changes, fail early

            entities = params[:entities]
            unless entities
              logger.debug("no entities object found in the following supplied JSON:")
              logger.debug(request.body)
              return err(403, "No entities object received")
            end
            return err(403, "The received entities object is not an Enumerable") unless entities.is_a?(Enumerable)
            return err(403, "Entity with a nil id detected") unless entities.any? {|e| !e['id'].nil?}

            created_ids = []
            entities.each do |entity|
              unless entity['id']
                errors << "Entity not imported as it has no id: #{entity.inspect}"
                next
              end
              Flapjack::Data::Entity.add(entity, :redis => redis)
              created_ids << entity['id']
            end

            return err(403, *errors) unless errors.empty?

            created_ids.to_json
          end

          # create a scheduled maintenance period for a check on an entity
          app.post %r{/scheduled_maintenances#{ENTITY_CHECK_FRAGMENT}} do
            captures    = params[:captures] || []
            entity_name = captures[0]
            check       = captures[1]

            entities, checks = entities_and_checks(entity_name, check)

            start_time = validate_and_parsetime(params[:start_time])
            halt( err(403, "start time must be provided") ) unless start_time

            act_proc = proc {|entity_check|
              entity_check.create_scheduled_maintenance(start_time,
                params[:duration].to_i, :summary => params[:summary])
            }

            bulk_api_check_action(entities, checks, act_proc)
            status 204
          end

          # create an acknowledgement for a service on an entity
          # NB currently, this does not acknowledge a specific failure event, just
          # the entity-check as a whole
          app.post %r{/acknowledgements#{ENTITY_CHECK_FRAGMENT}} do
            captures    = params[:captures] || []
            entity_name = captures[0]
            check       = captures[1]

            entities, checks = entities_and_checks(entity_name, check)

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

            bulk_api_check_action(entities, checks, act_proc)
            status 204
          end

          app.delete %r{/((?:un)?scheduled_maintenances)} do
            action = params[:captures][0]

            # no backwards-compatible mode here, it's a new method
            entities, checks = entities_and_checks(nil, nil)

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

            bulk_api_check_action(entities, checks, act_proc)
            status 204
          end

          app.post %r{/test_notifications#{ENTITY_CHECK_FRAGMENT}} do
            captures    = params[:captures] || []
            entity_name = captures[0]
            check       = captures[1]

            entities, checks = entities_and_checks(entity_name, check)

            act_proc = proc {|entity_check|
              summary = params[:summary] ||
                        "Testing notifications to all contacts interested in entity #{entity_check.entity.name}"
              Flapjack::Data::Event.test_notifications(
                entity_check.entity_name, entity_check.check,
                :summary => summary,
                :redis => redis)
            }

            bulk_api_check_action(entities, checks, act_proc)
            status 204
          end

        end

      end

    end

  end

end
