#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/entity'
require 'flapjack/data/entity_check'

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      module EntityMethods

        module Helpers

          def checks_for_entity_ids(entity_ids)
            return if entity_ids.nil?
            entity_ids.inject([]) do |memo, entity_id|
              entity = find_entity_by_id(entity_id)
              check_names = entity.check_list.sort
              check_names.each do |check_name|
                memo << find_entity_check(entity, check_name)
              end
              memo
            end
          end
        end

        def self.registered(app)
          app.helpers Flapjack::Gateways::JSONAPI::Helpers
          app.helpers Flapjack::Gateways::JSONAPI::EntityMethods::Helpers

          # Returns all (/entities) or some (/entities/A,B,C) or one (/entities/A) contact(s)
          # NB: only works with good data -- i.e. entity must have an id
          app.get %r{^/entities(?:/)?([^/]+)?$} do
            requested_entities = if params[:captures] && params[:captures][0]
              params[:captures][0].split(',').uniq
            else
              nil
            end

            entities = if requested_entities
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

            entities_json = entities.collect {|entity|
              entity.linked_contact_ids = linked_contact_ids[entity.id]
              entity.to_jsonapi
            }.join(", ")

            '{"entities":[' + entities_json + ']' +
                ',"linked":{"contacts":' + linked_contact_data.to_json + '}}'
          end

          app.post '/entities' do
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

          app.patch '/entities/:id' do
            params[:id].split(',').collect {|entity_id|
              find_entity_by_id(entity_id)
            }.each do |entity|
              apply_json_patch('entities') do |op, property, linked, value|
                case op
                when 'replace'
                  if ['name'].include?(property)
                    entity.update(property => value)
                  end
                when 'add'
                  if 'contacts'.eql?(linked)
                    contact = Flapjack::Data::Contact.find_by_id(value, :redis => redis)
                    contact.add_entity(entity) unless contact.nil?
                  end
                when 'remove'
                  if 'contacts'.eql?(linked)
                    contact = Flapjack::Data::Contact.find_by_id(value, :redis => redis)
                    contact.remove_entity(entity) unless contact.nil?
                  end
                end
              end
            end

            status 204
          end

          # create a scheduled maintenance period for a check on an entity
          app.post %r{^/scheduled_maintenances/entities/([^/]+)$} do
            entity_ids = params[:captures][0].split(',')

            start_time = validate_and_parsetime(params[:start_time])
            halt( err(403, "start time must be provided") ) unless start_time

            checks_for_entity_ids(entity_ids).each do |check|
              check.create_scheduled_maintenance(start_time,
                params[:duration].to_i, :summary => params[:summary])
            end

            response.headers['Location'] =
              "#{request.base_url}/scheduled_maintenance_report/entities/" + entity_ids.join(',') +
              "?start_time=#{params[:start_time]}"

            status 201
          end

          # create an acknowledgement for a service on an entity
          # NB currently, this does not acknowledge a specific failure event, just
          # the entity-check as a whole
          app.post %r{^/unscheduled_maintenances/entities/([^/]+)$} do
            entity_ids = params[:captures][0].split(',')

            dur = params[:duration] ? params[:duration].to_i : nil
            duration = (dur.nil? || (dur <= 0)) ? (4 * 60 * 60) : dur
            summary = params[:summary]

            opts = {'duration' => duration}
            opts['summary'] = summary if summary

            t = Time.now

            checks_for_entity_ids(entity_ids).each do |check|
              Flapjack::Data::Event.create_acknowledgement(
                check.entity_name, check.check,
                :summary => params[:summary],
                :duration => duration,
                :redis => redis)
            end

            response.headers['Location'] =
              "#{request.base_url}/unscheduled_maintenance_report/entities/" + entity_ids.join(',') +
              "?start_time=#{t.iso8601}"

            status 201
          end

          app.patch %r{^/unscheduled_maintenances/entities/([^/]+)$} do
            checks_for_entity_ids( params[:captures][0].split(',') ).each do |check|
              apply_json_patch('unscheduled_maintenances') do |op, property, linked, value|
                case op
                when 'replace'
                  if ['end_time'].include?(property)
                    end_time = validate_and_parsetime(value)
                    check.end_unscheduled_maintenance(end_time.to_i)
                  end
                end
              end
            end
            status 204
          end

          app.delete %r{^/scheduled_maintenances/entities/([^/]+)$} do
            start_time = validate_and_parsetime(params[:start_time])
            halt( err(403, "start time must be provided") ) unless start_time

            checks_for_entity_ids(params[:captures][0].split(',')).each do |check|
              check.end_scheduled_maintenance(start_time.to_i)
            end
            status 204
          end

          app.post %r{^/test_notifications/entities/([^/]+)$} do
            checks_for_entity_ids(params[:captures][0].split(',')).each do |check|
              summary = params[:summary] ||
                        "Testing notifications to all contacts interested in entity #{check.entity.name}"
              Flapjack::Data::Event.test_notifications(
                check.entity_name, check.check,
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
