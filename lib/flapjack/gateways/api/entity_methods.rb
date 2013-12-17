#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack'

require 'flapjack/data/entity'
require 'flapjack/data/check'
require 'flapjack/data/event'

require 'flapjack/gateways/api/entity_presenter'
require 'flapjack/gateways/api/check_presenter'

module Flapjack

  module Gateways

    class API < Sinatra::Base

      class CheckNotFound < RuntimeError
        attr_reader :entity_name, :check_name
        def initialize(entity_name, check_name)
          @entity_name = entity_name
          @check_name = check_name
        end
      end

      class EntityNotFound < RuntimeError
        attr_reader :entity_name
        def initialize(entity_name)
          @entity_name = entity_name
        end
      end

      module EntityMethods

        module Helpers

          def find_entity(entity_name)
            entity = Flapjack::Data::Entity.intersect(:name => entity_name).all.first
            raise Flapjack::Gateways::API::EntityNotFound.new(entity_name) if entity.nil?
            entity
          end

          def find_check(entity_name, check_name)
            check = Flapjack::Data::Check.intersect(:entity_name => entity_name, :name => check_name).all.first
            raise Flapjack::Gateways::API::CheckNotFound.new(entity_name, check_name) if check.nil?
            check
          end

          def find_entity_tags(tags)
            halt err(403, "no tags") if tags.nil? || tags.empty?
            return tags if tags.is_a?(Array)
            [tags]
          end

          def entity_and_check_names(entity_name, check_name)
            if entity_name
              # backwards-compatible, single entity or entity&check from route
              entity_names = check_name ? nil : [entity_name]
              check_names  = check_name ? {entity_name => check_name} : nil
            else
              # new and improved bulk API queries
              entity_names = params[:entity]
              check_names  = params[:check]
              entity_names = [entity_names] unless entity_names.nil? || entity_names.is_a?(Array)
              # TODO err if checks isn't a Hash (similar rules as in flapjack-diner)
            end
            [entity_names, check_names]
          end

          def bulk_api_check_action(entity_names, check_names)
            unless entity_names.nil? || entity_names.empty?
              entity_names.each do |entity_name|
                find_entity(entity_name).checks.all.sort_by(&:name).each do |check|
                  yield( check )
                end
              end
            end

            unless check_names.nil? || check_names.empty?
              check_names.each_pair do |entity_name, check_name_list|
                check_name_list = [check_name_list] unless check_name_list.is_a?(Array)
                check_name_list.each do |check_name|
                  yield( find_check(entity_name, check_name) )
                end
              end
            end
          end

          def present_api_results(entity_names, check_names, result_type)
            result = []

            unless entity_names.nil? || entity_names.empty?
              result += entity_names.collect {|entity_name|
                entity = find_entity(entity_name)
                yield(Flapjack::Gateways::API::EntityPresenter.new(entity))
              }.flatten(1)
            end

            unless check_names.nil? || check_names.empty?
              result += check_names.inject([]) {|memo, (entity_name, check_name_list)|
                check_name_list = [check_name_list] unless check_name_list.is_a?(Array)
                memo += check_name_list.collect {|check_name|
                  check = find_check(entity_name, check_name)
                  {:entity => entity_name,
                   :check => check_name,
                   result_type.to_sym => yield(Flapjack::Gateways::API::CheckPresenter.new(check))
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
            ret = Flapjack::Data::Entity.all.sort_by(&:name).collect {|e|
              presenter = Flapjack::Gateways::API::EntityPresenter.new(e)
              {'id' => e.id, 'name' => e.name, 'checks' => presenter.status }
            }
            ret.to_json
          end

          app.get '/checks/:entity' do
            content_type :json
            entity = find_entity(params[:entity])
            entity.checks.all.to_json
          end

          app.get %r{/status#{ENTITY_CHECK_FRAGMENT}} do
            content_type :json

            captures    = params[:captures] || []
            entity_name = captures[0]
            check_name  = captures[1]

            entity_names, check_names = entity_and_check_names(entity_name, check_name)

            results = present_api_results(entity_names, check_names, 'status') {|presenter|
              presenter.status
            }

            if entity_name
              # compatible with previous data format
              results = results.collect {|status_h| status_h[:status]}
              (check_name ? results.first : results).to_json
            else
              # new and improved data format which reflects the request param structure
              "[" + results.map {|r| r.to_json }.join(',') + "]"
            end
          end

          app.get %r{/((?:outages|(?:un)?scheduled_maintenances|downtime))#{ENTITY_CHECK_FRAGMENT}} do
            action      = params[:captures][0].to_sym
            entity_name = params[:captures][1]
            check_name  = params[:captures][2]

            entity_names, check_names = entity_and_check_names(entity_name, check_name)

            start_time = validate_and_parsetime(params[:start_time])
            end_time   = validate_and_parsetime(params[:end_time])

            results = present_api_results(entity_names, check_names, action) {|presenter|
              presenter.send(action, start_time, end_time)
            }

            if check_name
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
            check_name  = captures[1]

            entity_names, check_names = entity_and_check_names(entity_name, check_name)

            start_time = validate_and_parsetime(params[:start_time])
            halt( err(403, "start time must be provided") ) unless start_time

            act_proc = proc {|check|
              sched_maint = Flapjack::Data::ScheduledMaintenance.new(:start_time => start_time,
                :end_time => start_time + params[:duration].to_i,
                :summary => params[:summary])

              unless sched_maint.save
                halt( err(403, *sched_maint.errors.full_messages) )
              end

              check.add_scheduled_maintenance(sched_maint)
            }

            bulk_api_check_action(entity_names, check_names, &act_proc)
            status 204
          end

          # create an acknowledgement for a service on an entity
          # NB currently, this does not acknowledge a specific failure event, just
          # the entity-check as a whole
          app.post %r{/acknowledgements#{ENTITY_CHECK_FRAGMENT}} do
            captures    = params[:captures] || []
            entity_name = captures[0]
            check_name  = captures[1]

            entity_names, check_names = entity_and_check_names(entity_name, check_name)

            dur = params[:duration] ? params[:duration].to_i : nil
            duration = (dur.nil? || (dur <= 0)) ? (4 * 60 * 60) : dur
            summary = params[:summary]

            opts = {'duration' => duration}
            opts['summary'] = summary if summary

            act_proc = proc {|check|
              Flapjack::Data::Event.create_acknowledgement(
                config['processor_queue'] || 'events',
                check.entity_name, check.name,
                :summary => params[:summary],
                :duration => duration)
            }

            bulk_api_check_action(entity_names, check_names, &act_proc)
            status 204
          end

          app.delete %r{/((?:un)?scheduled_maintenances)} do
            action = params[:captures][0]

            # no backwards-compatible mode here, it's a new method
            entity_names, check_names = entity_and_check_names(nil, nil)

            act_proc = case action
            when 'scheduled_maintenances'
              start_time = validate_and_parsetime(params[:start_time])
              halt( err(403, "start time must be provided") ) unless start_time
              opts = {}
              proc {|check|
                next unless sched_maint = check.scheduled_maintenances_by_start.
                  intersect_range(start_time.to_i, start_time.to_i, :by_score => true).all.first
                check.end_scheduled_maintenance(sched_maint, Time.now)
              }
            when 'unscheduled_maintenances'
              end_time = validate_and_parsetime(params[:end_time])
              proc {|check| check.clear_unscheduled_maintenance(end_time) }
            end

            bulk_api_check_action(entity_names, check_names, &act_proc)
            status 204
          end

          app.post %r{/test_notifications#{ENTITY_CHECK_FRAGMENT}} do
            captures    = params[:captures] || []
            entity_name = captures[0]
            check_name  = captures[1]

            entity_names, check_names = entity_and_check_names(entity_name, check_name)

            act_proc = proc {|check|
              summary = params[:summary] ||
                        "Testing notifications to all contacts interested in entity #{check.entity.name}"
              Flapjack::Data::Event.test_notifications(
                config['processor_queue'] || 'events',
                check.entity_name, check.name,
                :summary => summary)
            }

            bulk_api_check_action(entity_names, check_names, &act_proc)
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

              if entity = Flapjack::Data::Entity.intersect(:name => ent['name']).all.first
                enabled = entity.enabled
                entity.destroy
              end

              entity = Flapjack::Data::Entity.new(:id => ent['id'], :name => ent['name'],
                :enabled => enabled)
              if entity.valid?
                if errors.empty?
                  entities_to_save << entity
                  if ent['contacts'] && ent['contacts'].respond_to?(:collect)
                    entity_contacts[ent['id']] = ent['contacts'].collect {|contact_id|
                      Flapjack::Data::Contact.find_by_id(contact_id)
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
