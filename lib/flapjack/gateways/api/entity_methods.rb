#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack'

require 'flapjack/data/entity_r'
require 'flapjack/data/entity_check_r'
require 'flapjack/data/event'

require 'flapjack/gateways/api/entity_presenter'
require 'flapjack/gateways/api/entity_check_presenter'

module Flapjack

  module Gateways

    class API < Sinatra::Base

      class EntityCheckNotFound < RuntimeError
        attr_reader :entity, :check
        def initialize(entity, check)
          @entity = entity
          @check = check
        end
      end

      class EntityNotFound < RuntimeError
        attr_reader :entity
        def initialize(entity)
          @entity = entity
        end
      end

      module EntityMethods

        module Helpers

          def find_entity(entity_name)
            entity = Flapjack::Data::EntityR.intersect(:name => entity_name).all.first
            raise Flapjack::Gateways::API::EntityNotFound.new(entity_name) if entity.nil?
            entity
          end

          def find_entity_check(entity_name, check_name)
            entity_check = Flapjack::Data::EntityCheckR.intersect(:entity_name => entity_name, :name => check_name).all.first
            raise Flapjack::Gateways::API::EntityCheckNotFound.new(entity_name, check_name) if entity_check.nil?
            entity_check
          end

          def find_entity_tags(tags)
            halt err(403, "no tags") if tags.nil? || tags.empty?
            return tags if tags.is_a?(Array)
            [tags]
          end

          def entities_and_checks(entity_name, check_name)
            if entity_name
              # backwards-compatible, single entity or entity&check from route
              entities = check_name ? nil : [entity_name]
              checks   = check_name ? {entity_name => check_name} : nil
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
                checks.each do |check_name|
                  action.call( find_entity_check(entity_name, check_name) )
                end
              end
            end

            unless entity_checks.nil? || entity_checks.empty?
              entity_checks.each_pair do |entity_name, checks|
                checks = [checks] unless checks.is_a?(Array)
                checks.each do |check|
                  action.call( find_entity_check(entity_name, check) )
                end
              end
            end
          end

          def present_api_results(entities, entity_checks, result_type, &block)
            result = []

            unless entities.nil? || entities.empty?
              result += entities.collect {|entity_name|
                entity = find_entity(entity_name)
                yield(Flapjack::Gateways::API::EntityPresenter.new(entity))
              }.flatten(1)
            end

            unless entity_checks.nil? || entity_checks.empty?
              result += entity_checks.inject([]) {|memo, (entity_name, checks)|
                checks = [checks] unless checks.is_a?(Array)
                memo += checks.collect {|check|
                  entity_check = find_entity_check(entity_name, check)
                  {:entity => entity_name,
                   :check => check,
                   result_type.to_sym => yield(Flapjack::Gateways::API::EntityCheckPresenter.new(entity_check))
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

          app.helpers Flapjack::Gateways::API::EntityMethods::Helpers

          app.get '/entities' do
            content_type :json
            ret = Flapjack::Data::EntityR.all.sort_by(&:name).collect {|e|
              presenter = Flapjack::Gateways::API::EntityPresenter.new(e)
              {'id' => e.id, 'name' => e.name, 'checks' => presenter.status }
            }
            ret.to_json
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
              (check ? results.first : results).to_json
            else
              # new and improved data format which reflects the request param structure
              results.to_json
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
              sched_maint = Flapjack::Data::ScheduledMaintenanceR.new(:start_time => start_time,
                :end_time => start_time + params[:duration].to_i,
                :summary => params[:summary])

              unless sched_maint.save
                halt( err(403, *sched_maint.errors.full_messages) )
              end

              entity_check.add_scheduled_maintenance(sched_maint)
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
                config['processor_queue'] || 'events',
                entity_check.entity_name, entity_check.check,
                :summary => params[:summary],
                :duration => duration)
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
              proc {|entity_check|
                next unless sched_maint = entity_check.scheduled_maintenances_by_start.
                  intersect_range(start_time.to_i, start_time.to_i, :by_score => true).all.first
                entity_check.end_scheduled_maintenance(sched_maint, Time.now.to_i)
              }
            when 'unscheduled_maintenances'
              end_time = validate_and_parsetime(params[:end_time])
              proc {|entity_check| entity_check.clear_unscheduled_maintenance(end_time) }
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
                config['processor_queue'] || 'events',
                entity_check.entity_name, entity_check.check,
                :summary => summary)
            }

            bulk_api_check_action(entities, checks, act_proc)
            status 204
          end

          app.post '/entities' do
            pass unless 'application/json'.eql?(request.content_type)

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

            entities_to_save = []
            entity_contacts = {}
            entities.each do |ent|
              unless ent['id']
                errors << "Entity not imported as it has no id: #{ent.inspect}"
                next
              end

              enabled = false

              if entity = Flapjack::Data::EntityR.intersect(:name => ent['name']).all.first
                enabled = entity.enabled
                entity.destroy
              end

              entity = Flapjack::Data::EntityR.new(:id => ent['id'], :name => ent['name'],
                :enabled => enabled)
              if entity.valid?
                if errors.empty?
                  entities_to_save << entity
                  if ent['contacts'] && ent['contacts'].respond_to?(:collect)
                    entity_contacts[ent['id']] = ent['contacts'].collect {|contact_id|
                      Flapjack::Data::ContactR.find_by_id(contact_id)
                    }.compact
                  end
                end
              else
                errors << entity.errors.full_messages.join(", ")
              end
            end

            unless errors.empty?
              halt err(403, *errors)
            end

            entities_to_save.each {|entity|
              entity.save
              entity_contacts[entity.id].each do |contact|
                entity.contacts << contact
                contact.entities << entity
              end
            }
            204
          end

          app.post '/entities/:entity/tags' do
            content_type :json

            tags = find_entity_tags(params[:tag])
            entity = find_entity(params[:entity])
            entity.tags += tags
            entity.save
            entity.tags.to_json
          end

          app.delete '/entities/:entity/tags' do
            tags = find_entity_tags(params[:tag])
            entity = find_entity(params[:entity])
            entity.tags -= tags
            entity.save
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
