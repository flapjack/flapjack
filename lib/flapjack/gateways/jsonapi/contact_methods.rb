#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/contact'
require 'flapjack/data/notification_rule'

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      module ContactMethods

        SEMAPHORE_CONTACT_MASS_UPDATE = 'contact_mass_update'

        module Helpers

          def check_errors_on_save(record)
            return if record.save
            halt err(403, *record.errors.full_messages)
          end

          def bulk_contact_operation(contact_ids, &block)
            missing_ids = nil
            Flapjack::Data::Contact.backend.lock(Flapjack::Data::Contact) do
              contacts = Flapjack::Data::Contact.find_by_ids(*contact_ids)
              missing_ids = contact_ids - contacts.map(&:id)
              block.call(contacts) if missing_ids.empty?
            end

            unless missing_ids.empty?
              halt(404, "Contacts with ids #{missing_ids.join(', ')} were not found")
            end
          end

        end

        def self.registered(app)
          app.helpers Flapjack::Gateways::JSONAPI::Helpers
          app.helpers Flapjack::Gateways::JSONAPI::ContactMethods::Helpers

          app.post '/contacts' do
            contacts_data = wrapped_params('contacts')

            data_ids = contacts_data.reject {|c| c['id'].nil? }.
              map {|co| co['id'].to_s }

            contact_err = nil
            contact_ids = nil
            contacts    = nil

            Flapjack::Data::Contact.backend.lock(Flapjack::Data::Contact) do

              # TODO should these overwrite instead?
              conflicted_ids = data_ids.select {|id|
                Flapjack::Data::Contact.exists?(id)
              }

              if conflicted_ids.length > 0
                contact_err = "Contacts already exist with the following ids: " +
                                conflicted_ids.join(', ')
              else
                contacts = contacts_data.collect do |contact_data|
                  Flapjack::Data::Contact.new(:id => contact_data['id'],
                    :first_name => contact_data['first_name'],
                    :last_name => contact_data['last_name'],
                    :email => contact_data['email'],
                    :timezone => contact_data['timezone'],
                    :tags => contact_data['tags'])
                end
              end

              if invalid = contacts.detect {|c| c.invalid? }
                contact_err = "Contact validation failed, " + invalid.errors.full_messages.join(', ')
              else
                contact_ids = contacts.collect {|c| c.save; c.id }
              end
            end

            if contact_err
              halt err(403, contact_err)
            end

            status 201
            response.headers['Location'] = "#{base_url}/contacts/#{contact_ids.join(',')}"
            contact_ids.to_json
          end

          # Returns all (/contacts) or some (/contacts/1,2,3) or one (/contacts/2) contact(s)
          # http://flapjack.io/docs/1.0/jsonapi/#contacts
          app.get %r{^/contacts(?:/)?([^/]+)?$} do
            requested_contacts = if params[:captures] && params[:captures][0]
              params[:captures][0].split(',').uniq
            else
              nil
            end

            contacts = if requested_contacts
              Flapjack::Data::Contact.find_by_ids!(*requested_contacts)
            else
              Flapjack::Data::Contact.all
            end

            if requested_contacts && contacts.empty?
              raise Flapjack::Gateways::JSONAPI::RecordsNotFound.new(Flapjack::Data::Contact, requested_contacts)
            end

            contacts_ids = contacts.map(&:id)
            linked_entity_ids = Flapjack::Data::Contact.associated_ids_for_entities(contacts_ids)
            linked_medium_ids = Flapjack::Data::Contact.associated_ids_for_media(contacts_ids)
            linked_pagerduty_credentials_ids = Flapjack::Data::Contact.associated_ids_for_pagerduty_credentials(contacts_ids)
            linked_notification_rule_ids = Flapjack::Data::Contact.associated_ids_for_notification_rules(contacts_ids)

            contacts_json = contacts.collect {|contact|
              contact.as_json(:entity_ids => linked_entity_ids[contact.id],
                :medium_ids => linked_medium_ids[contact.id],
                :pagerduty_credentials_ids => linked_pagerduty_credentials_ids[contact.id],
                :notification_rule_ids => linked_notification_rule_ids[contact.id]).to_json
            }.join(", ")

            '{"contacts":[' + contacts_json + ']}'
          end

          app.patch '/contacts/:id' do
            bulk_contact_operation(params[:id].split(',')) do |contacts|
              contacts.each do |contact|
                apply_json_patch('contacts') do |op, property, linked, value|
                  case op
                  when 'replace'
                    if ['first_name', 'last_name', 'email', 'timezone', 'tags'].include?(property)
                      contact.send("#{property}=".to_sym, value)
                    end
                  when 'add'
                    case linked
                    when 'entities'
                      entity = Flapjack::Data::Entity.find_by_id(value)
                      contact.entities << entity unless entity.nil?
                    when 'media'
                      Flapjack::Data::Medium.backend.lock(Flapjack::Data::Medium) do
                        medium = Flapjack::Data::Medium.find_by_id(value)
                        unless medium.nil?
                          if existing_medium = contact.media.intersect(:type => medium.type).all.first
                            # TODO is this the right thing to do here? -- or just dissociate?
                            existing_medium.destroy
                          end
                          contact.media << medium
                        end
                      end
                    when 'notification_rules'
                      notification_rule = Flapjack::Data::NotificationRule.find_by_id(value)
                      contact.notification_rules << notification_rule unless notification_rule.nil?
                    end
                  when 'remove'
                    case linked
                    when 'entities'
                      entity = Flapjack::Data::Entity.find_by_id(value)
                      contact.entities.delete(entity) unless entity.nil?
                    when 'media'
                      medium = Flapjack::Data::Medium.find_by_id(value)
                      contact.media.delete(medium) unless medium.nil?
                    when 'notification_rules'
                      notification_rule = Flapjack::Data::NotificationRule.find_by_id(value)
                      contact.notification_rules.delete(notification_rule) unless notification_rule.nil?
                    end
                  end
                end
                contact.save # no-op if the properties haven't changed
              end
            end

            status 204
          end

          app.delete '/contacts/:id' do
            bulk_contact_operation(params[:id].split(',')) do |contacts|
              contacts.map(&:destroy)
            end

            status 204
          end

        end

      end

    end

  end

end
