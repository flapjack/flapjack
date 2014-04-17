#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/contact'
require 'flapjack/data/notification_rule'
require 'flapjack/data/semaphore'

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      module ContactMethods

        SEMAPHORE_CONTACT_MASS_UPDATE = 'contact_mass_update'

        module Helpers

          def obtain_semaphore(resource)
            semaphore = nil
            strikes = 0
            begin
              semaphore = Flapjack::Data::Semaphore.new(resource, :redis => redis, :expiry => 30)
            rescue Flapjack::Data::Semaphore::ResourceLocked
              strikes += 1
              raise Flapjack::Gateways::JSONAPI::ResourceLocked.new(resource) unless strikes < 3
              sleep 1
              retry
            end
            raise Flapjack::Gateways::JSONAPI::ResourceLocked.new(resource) unless semaphore
            semaphore
          end

          def bulk_contact_operation(contact_ids, &block)
            semaphore = obtain_semaphore(SEMAPHORE_CONTACT_MASS_UPDATE)

            contacts_by_id = contact_ids.inject({}) do |memo, contact_id|
              # can't use find_contact here as that would halt immediately
              memo[contact_id] = Flapjack::Data::Contact.find_by_id(contact_id, :redis => redis, :logger => logger)
              memo
            end

            missing_ids = contacts_by_id.select {|k, v| v.nil? }.keys
            unless missing_ids.empty?
              semaphore.release
              halt(404, "Contacts with ids #{missing_ids.join(', ')} were not found")
            end

            block.call(contacts_by_id.select {|k, v| !v.nil? }.values)
            semaphore.release
          end

        end

        def self.registered(app)
          app.helpers Flapjack::Gateways::JSONAPI::Helpers
          app.helpers Flapjack::Gateways::JSONAPI::ContactMethods::Helpers

          app.post '/contacts' do
            contacts_data = params[:contacts]

            if contacts_data.nil? || !contacts_data.is_a?(Enumerable)
              halt err(422, "No valid contacts were submitted")
            end

            contacts_ids = contacts_data.reject {|c| c['id'].nil? }.
              map {|co| co['id'].to_s }

            semaphore = obtain_semaphore(SEMAPHORE_CONTACT_MASS_UPDATE)

            conflicted_ids = contacts_ids.find_all {|id|
              Flapjack::Data::Contact.exists_with_id?(id, :redis => redis)
            }

            unless conflicted_ids.empty?
              semaphore.release
              halt err(409, "Contacts already exist with the following IDs: " +
                conflicted_ids.join(', '))
            end

            contacts_data.each do |contact_data|
              unless contact_data['id']
                contact_data['id'] = SecureRandom.uuid
              end
              Flapjack::Data::Contact.add(contact_data, :redis => redis)
            end

            semaphore.release

            ids = contacts_data.map {|c| c['id']}
            location(ids)

            contacts_data.map {|cd| cd['id']}.to_json
          end

          # Returns all (/contacts) or some (/contacts/1,2,3) or one (/contacts/2) contact(s)
          # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts
          app.get %r{^/contacts(?:/)?([^/]+)?$} do
            requested_contacts = if params[:captures] && params[:captures][0]
              params[:captures][0].split(',').uniq
            else
              nil
            end

            contacts = if requested_contacts
              Flapjack::Data::Contact.find_by_ids(requested_contacts, :logger => logger, :redis => redis)
            else
              Flapjack::Data::Contact.all(:redis => redis)
            end
            contacts.compact!

            if requested_contacts && contacts.empty?
              raise Flapjack::Gateways::JSONAPI::ContactsNotFound.new(requested_contacts)
            end

            entity_ids = Flapjack::Data::Contact.entity_ids_for(contacts.map(&:id), :redis => redis)

            contacts_json = contacts.collect {|contact|
              contact.to_jsonapi(:entity_ids => entity_ids[contact.id])
            }.join(", ")

            '{"contacts":[' + contacts_json + ']}'
          end

          app.patch '/contacts/:id' do
            bulk_contact_operation(params[:id].split(',')) do |contacts|
              contacts.each do |contact|
                apply_json_patch('contacts') do |op, property, linked, value|
                  case op
                  when 'replace'
                    if ['first_name', 'last_name', 'email'].include?(property)
                      contact.update(property => value)
                    end
                  when 'add'
                    case linked
                    when 'entities'
                      entity = Flapjack::Data::Entity.find_by_id(value, :redis => redis)
                      contact.add_entity(entity) unless entity.nil?
                    when 'notification_rules'
                      notification_rule = Flapjack::Data::NotificationRule.find_by_id(value, :redis => redis)
                      unless notification_rule.nil?
                        contact.grab_notification_rule(notification_rule)
                      end
                    # when 'media' # not supported yet due to id brokenness
                    end
                  when 'remove'
                    case linked
                    when 'entities'
                      entity = Flapjack::Data::Entity.find_by_id(value, :redis => redis)
                      contact.remove_entity(entity) unless entity.nil?
                    when 'notification_rules'
                      notification_rule = Flapjack::Data::NotificationRule.find_by_id(value, :redis => redis)
                      unless notification_rule.nil?
                        contact.delete_notification_rule(notification_rule)
                      end
                    # when 'media' # not supported yet due to id brokenness
                    end
                  end
                end
              end
            end

            status 204
          end

          # Delete one or more contacts
          app.delete '/contacts/:id' do
            bulk_contact_operation(params[:id].split(',')) do |contacts|
              contacts.each {|contact| contact.delete!}
            end

            status 204
          end

        end

      end

    end

  end

end
