#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/entity'
require 'flapjack/data/entity_check'

require 'flapjack/gateways/jsonapi/entity_presenter'
require 'flapjack/gateways/jsonapi/entity_check_presenter'

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

          def find_entity_check(entity, check)
            entity_check = Flapjack::Data::EntityCheck.for_entity(entity,
              check, :redis => redis)
            raise Flapjack::Gateways::JSONAPI::EntityCheckNotFound.new(entity, check) if entity_check.nil?
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

          def present_api_results(entities, entity_checks, result_type, &block)
            result = []

            unless entities.nil? || entities.empty?
              result += entities.collect {|entity_name|
                entity = find_entity(entity_name)
                yield(Flapjack::Gateways::JSONAPI::EntityPresenter.new(entity, :redis => redis))
              }.flatten(1)
            end

            unless entity_checks.nil? || entity_checks.empty?
              result += entity_checks.inject([]) {|memo, (entity_name, checks)|
                checks = [checks] unless checks.is_a?(Array)
                entity = find_entity(entity_name)
                memo += checks.collect {|check|
                  entity_check = find_entity_check(entity, check)
                  {:entity => entity_name,
                   :check => check,
                   result_type.to_sym => yield(Flapjack::Gateways::JSONAPI::EntityCheckPresenter.new(entity_check))
                  }
                }
              }.flatten(1)
            end

            result
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

          app.get '/entities' do
            content_type :json
            cors_headers

            entities_json = Flapjack::Data::Entity.all(:redis => redis).collect {|e|
              presenter = Flapjack::Gateways::JSONAPI::EntityPresenter.new(e, :redis => redis)
              id = (e.id.respond_to?(:length) && e.id.length > 0) ? e.id : e.name
              {'id' => id, 'name' => e.name, 'checks' => presenter.status }.to_json
            }.join(',')

            '{"entities":[' + entities_json + ']}'
          end

          app.get '/checks/:entity' do
            content_type :json
            entity = find_entity(params[:entity])
            entity.check_list.to_json
          end

          app.get %r{/status#{ENTITY_CHECK_FRAGMENT}} do
            content_type :json

            captures    = params[:captures] || []
            entity_name = captures[0]
            check       = captures[1]

            entities, checks = entities_and_checks(entity_name, check)

            results = present_api_results(entities, checks, 'status') {|presenter|
              presenter.status
            }

            if entity_name
              # compatible with previous data format
              results = results.collect {|status_h| status_h[:status]}
              check ? results.first.to_json : "[" + results.map {|r| r.to_json }.join(',') + "]"
            else
              # new and improved data format which reflects the request param structure
              "[" + results.map {|r| r.to_json }.join(',') + "]"
            end
          end

          app.get %r{/((?:outages|(?:un)?scheduled_maintenances|downtime))#{ENTITY_CHECK_FRAGMENT}} do
            action      = params[:captures][0].to_sym
            entity_name = params[:captures][1]
            check       = params[:captures][2]

            entities, checks = entities_and_checks(entity_name, check)

            start_time = validate_and_parsetime(params[:start_time])
            end_time   = validate_and_parsetime(params[:end_time])

            results = present_api_results(entities, checks, action) {|presenter|
              presenter.send(action, start_time, end_time)
            }

            if check
              # compatible with previous data format
              results.first[action].to_json
            elsif entity_name
              # compatible with previous data format
              rename = {:unscheduled_maintenances => :unscheduled_maintenance,
                        :scheduled_maintenances   => :scheduled_maintenance}
              drop   = [:entity]
              results.collect{|r|
                r.inject({}) {|memo, (k, v)|
                  if new_k = rename[k]
                    memo[new_k] = v
                  elsif !drop.include?(k)
                    memo[k] = v
                  end
                 memo
                }
              }.to_json
            else
              # new and improved data format which reflects the request param structure
              results.to_json
            end
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

          app.post '/entities' do
            pass unless Flapjack::Gateways::JSONAPI::JSON_REQUEST_MIME_TYPES.include?(request.content_type)

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

            entities.each do |entity|
              unless entity['id']
                errors << "Entity not imported as it has no id: #{entity.inspect}"
                next
              end
              Flapjack::Data::Entity.add(entity, :redis => redis)
            end
            errors.empty? ? 204 : err(403, *errors)
          end

          app.post '/entities/:entity/tags' do
            content_type :json

            tags = find_tags(params[:tag])
            entity = find_entity(params[:entity])
            entity.add_tags(*tags)
            entity.tags.to_json
          end

          app.delete '/entities/:entity/tags' do
            tags = find_tags(params[:tag])
            entity = find_entity(params[:entity])
            entity.delete_tags(*tags)
            status 204
          end

          app.get '/entities/:entity/tags' do
            content_type :json

            entity = find_entity(params[:entity])
            entity.tags.to_json
          end

        end

      end

    end

  end

end
