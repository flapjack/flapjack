#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/check'
require 'flapjack/data/entity'
require 'flapjack/data/event'

require 'flapjack/gateways/jsonapi/check_methods_helpers'

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      module EntityMethods

        def self.registered(app)
          app.helpers Flapjack::Gateways::JSONAPI::Helpers
          app.helpers Flapjack::Gateways::JSONAPI::CheckMethods::Helpers

          app.post '/entities' do
            entities_data = wrapped_params('entities')

            entity_err = nil
            entity_ids = nil
            entities   = nil

           data_ids = entities_data.reject {|c| c['id'].nil? }.
              map {|co| co['id'].to_s }

            Flapjack::Data::Entity.send(:lock) do

              conflicted_ids = data_ids.select {|id|
                Flapjack::Data::Entity.exists?(id)
              }

              if conflicted_ids.length > 0
                contact_err = "Entities already exist with the following ids: " +
                                conflicted_ids.join(', ')
              else
                entities = entities_data.collect do |ed|
                  Flapjack::Data::Entity.new(:id => ed['id'], :name => ed['name'],
                    :enabled => ed['enabled'], :tags => ed['tags'])
                end
              end

              if invalid = entities.detect {|c| c.invalid? }
                entity_err = "Entity validation failed, " + invalid.errors.full_messages.join(', ')
              else
                entity_ids = entities.collect {|e| e.save; e.id }
              end

            end

            if entity_err
              halt err(403, entity_err)
            end

            status 201
            response.headers['Location'] = "#{base_url}/entities/#{entity_ids.join(',')}"
            entity_ids.to_json
          end

          # Returns all (/entities) or some (/entities/A,B,C) or one (/entities/A) contact(s)
          # NB: only works with good data -- i.e. entity must have an id
          app.get %r{^/entities(?:/)?([^/]+)?$} do
            requested_entities = if params[:captures] && params[:captures][0]
              params[:captures][0].split(',').uniq
            else
              nil
            end

            entities = if requested_entities
              Flapjack::Data::Entity.find_by_ids!(requested_entities)
            else
              Flapjack::Data::Entity.all
            end

            if requested_entities && entities.empty?
              raise Flapjack::Gateways::JSONAPI::RecordsNotFound.new(Flapjack::Data::Entity, requested_entities)
            end

            entities_ids = entities.map(&:id)
            linked_contacts_ids = Flapjack::Data::Entity.associated_ids_for_contacts(entities_ids)
            linked_checks_ids  = Flapjack::Data::Entity.associated_ids_for_checks(entities_ids)

            entities_json = entities.collect {|entity|
              entity.as_json(:contacts_ids => linked_contacts_ids[entity.id],
                             :checks_ids   => linked_checks_ids[entity.id]).to_json
            }.join(",")

            '{"entities":[' + entities_json + ']}'
          end

          app.patch '/entities/:id' do
            Flapjack::Data::Entity.find_by_ids!(params[:id].split(',')).each do |entity|
              apply_json_patch('entities') do |op, property, linked, value|
                case op
                when 'replace'
                  if ['name', 'enabled', 'tags'].include?(property)
                    entity.send("#{property}=".to_sym, value)
                  end
                when 'add'
                  if 'contacts'.eql?(linked)
                    contact = Flapjack::Data::Contact.find_by_id(value)
                    contact.entities << entity unless contact.nil?
                  end
                when 'remove'
                  if 'contacts'.eql?(linked)
                    contact = Flapjack::Data::Contact.find_by_id(value)
                    contact.entities.delete(entity) unless contact.nil?
                  end
                end
              end
              entity.save # no-op if it hasn't changed
            end

            status 204
          end

          app.delete '/entities/:id' do
            Flapjack::Data::Entity.find_by_ids!(params[:id].split(',')).map(&:destroy)

            status 204
          end

          app.post %r{^/scheduled_maintenances/entities/([^/]+)$} do
            entity_ids = params[:captures][0].split(',')
            check_ids = Flapjack::Data::Entity.associated_ids_for_checks(entity_ids).values.flatten(1)
            create_scheduled_maintenances(check_ids)
          end

          # NB this does not acknowledge a specific failure event, just
          # the entity-check as a whole
          app.post %r{^/unscheduled_maintenances/entities/([^/]+)$} do
            entity_ids = params[:captures][0].split(',')
            check_ids = Flapjack::Data::Entity.associated_ids_for_checks(entity_ids).values.flatten(1)
            create_unscheduled_maintenances(check_ids)
          end

          app.patch %r{^/unscheduled_maintenances/entities/([^/]+)$} do
            entity_ids = params[:captures][0].split(',')
            check_ids = Flapjack::Data::Entity.associated_ids_for_checks(entity_ids).values.flatten(1)
            update_unscheduled_maintenances(check_ids)
          end

          app.delete %r{^/scheduled_maintenances/entities/([^/]+)$} do
            start_time = validate_and_parsetime(params[:start_time])
            halt( err(403, "start time must be provided") ) unless start_time

            entity_ids = params[:captures][0].split(',')
            check_ids = Flapjack::Data::Entity.associated_ids_for_checks(entity_ids).values.flatten(1)
            delete_scheduled_maintenances(start_time, check_ids)
          end

          app.post %r{^/test_notifications/entities/([^/]+)$} do
            entity_ids = params[:captures][0].split(',')
            check_ids = Flapjack::Data::Entity.associated_ids_for_checks(entity_ids).values.flatten(1)
            create_test_notifications(check_ids)
          end

        end

      end

    end

  end

end
