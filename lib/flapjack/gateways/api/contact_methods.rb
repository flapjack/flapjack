#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/contact'
require 'flapjack/data/notification_rule'

module Flapjack

  module Gateways

    class API < Sinatra::Base

      class ContactNotFound < RuntimeError
        attr_reader :contact_id
        def initialize(contact_id)
          @contact_id = contact_id
        end
      end

      class NotificationuleNotFound < RuntimeError
        attr_reader :rule_id
        def initialize(rule_id)
          @rule_id = rule_id
        end
      end

      module ContactMethods

        module Helpers

          def find_contact(contact_id)
            contact = Flapjack::Data::Contact.find_by_id(contact_id)
            raise Flapjack::Gateways::API::ContactNotFound.new(contact_id) if contact.nil?
            contact
          end

          def find_rule(rule_id)
            rule = Flapjack::Data::NotificationRule.find_by_id(rule_id)
            raise Flapjack::Gateways::API::NotificationuleNotFound.new(rule_id) if rule.nil?
            rule
          end

          def find_contact_tags(tags)
            halt err(403, "no tags") if tags.nil? || tags.empty?
            return tags if tags.is_a?(Array)
            [tags]
          end

          def check_errors_on_save(record)
            return if record.save
            halt err(403, *record.errors.full_messages)
          end

        end

        def self.registered(app)

          app.helpers Flapjack::Gateways::API::ContactMethods::Helpers

          app.post '/contacts' do
            pass unless 'application/json'.eql?(request.content_type)
            content_type :json

            errors = []

            contacts_data = params[:contacts]
            if contacts_data.nil? || !contacts_data.is_a?(Enumerable)
              errors << "No valid contacts were submitted"
            else
              # stringifying as integer string params are automatically integered,
              # but our redis ids are strings
              contacts_data_ids = contacts_data.reject {|c| c['id'].nil? }.
                map {|co| co['id'].to_s }

              if contacts_data_ids.empty?
                errors << "No contacts with IDs were submitted"
              else
                contacts = Flapjack::Data::Contact.all
                contacts_h = hashify(*contacts) {|c| [c.id, c] }
                contacts_ids = contacts_h.keys

                # delete contacts not found in the bulk list
                (contacts_ids - contacts_data_ids).each do |contact_to_delete_id|
                  contact_to_delete = contacts.detect {|c| c.id == contact_to_delete_id }
                  contact_to_delete.destroy
                end

                # add or update contacts found in the bulk list
                contacts_data.reject {|cd| cd['id'].nil? }.each do |contact_data|

                  contact = contacts_h[contact_data['id'].to_s] ||
                            Flapjack::Data::Contact.new(:id => contact_data['id'].to_s)
                  contact.first_name = contact_data['first_name']
                  contact.last_name  = contact_data['last_name']
                  contact.email      = contact_data['email']
                  contact.save

                  unless contact_data['media'].nil?
                    contact.pagerduty_credentials.clear
                    contact.media.each {|medium|
                      contact.media.delete(medium)
                      medium.destroy
                    }

                    contact_data['media'].each_pair do |type, details|
                      medium = Flapjack::Data::Medium.new(:type => type)
                      case type
                      when 'pagerduty'
                        medium.address  = details['service_key']
                        contact.pagerduty_credentials = {
                          :subdomain => details['subdomain'],
                          :username  => details['username'],
                          :password  => details['password'],
                        }
                        contact.save
                      else
                        medium.address = details
                      end
                      medium.save
                      contact.media << medium
                    end
                  end
                end
              end
            end
            errors.empty? ? 204 : err(403, *errors)
          end

          # Returns all the contacts
          # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts
          app.get '/contacts' do
            content_type :json
            Flapjack::Data::Contact.all.collect {|c|
              c.as_json(:only => [:first_name, :last_name, :email, :tags])
            }.to_json
          end

          # Returns the core information about the specified contact
          # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts_id
          app.get '/contacts/:contact_id' do
            content_type :json

            contact = find_contact(params[:contact_id])
            contact.as_json(:only => [:first_name, :last_name, :email, :tags]).to_json
          end

          # Lists this contact's notification rules
          # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts_id_notification_rules
          app.get '/contacts/:contact_id/notification_rules' do
            content_type :json

            contact = find_contact(params[:contact_id])
            contact.notification_rules.all.collect {|nr|
              nr.as_json
            }.to_json
          end

          # Get the specified notification rule for this user
          # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts_id_notification_rules_id
          app.get '/notification_rules/:id' do
            content_type :json

            find_rule(params[:id]).to_json
          end

          # Creates a notification rule for a contact
          # https://github.com/flpjck/flapjack/wiki/API#wiki-post_contacts_id_notification_rules
          app.post '/notification_rules' do
            content_type :json

            if params[:id]
              halt err(403, "POST cannot be used for update, do a PUT instead")
            end

            logger.debug("POST /notification_rules data: ")
            logger.debug(params.inspect)

            contact = find_contact(params[:contact_id])

            tag_data = case params[:tags]
            when Array
              Set.new(params[:tags])
            when String
              Set.new([params[:tags]])
            else
              Set.new
            end

            notification_rule = Flapjack::Data::NotificationRule.new(
              :entities           => params[:entities],
              :tags               => tag_data,
              :time_restrictions  => params[:time_restrictions],
              :unknown_media      => params[:unknown_media],
              :warning_media      => params[:warning_media],
              :critical_media     => params[:critical_media],
              :unknown_blackhole  => !!params[:unknown_blackhole],
              :warning_blackhole  => !!params[:warning_blackhole],
              :critical_blackhole => !!params[:critical_blackhole],
            )

            check_errors_on_save(notification_rule)
            contact.notification_rules << notification_rule

            notification_rule.to_json
          end

          # Updates a notification rule
          # https://github.com/flpjck/flapjack/wiki/API#wiki-put_notification_rules_id
          app.put('/notification_rules/:id') do
            content_type :json

            logger.debug("PUT /notification_rules/#{params[:id]} data: ")
            logger.debug(params.inspect)

            notification_rule = find_rule(params[:id])

            tag_data = case params[:tags]
            when Array
              Set.new(params[:tags])
            when String
              Set.new([params[:tags]])
            else
              Set.new
            end

            {:entities           => params[:entities],
             :tags               => tag_data,
             :time_restrictions  => params[:time_restrictions],
             :unknown_media      => params[:unknown_media],
             :warning_media      => params[:warning_media],
             :critical_media     => params[:critical_media],
             :unknown_blackhole  => !!params[:unknown_blackhole],
             :warning_blackhole  => !!params[:warning_blackhole],
             :critical_blackhole => !!params[:critical_blackhole]}.each_pair do |att, value|

              notification_rule.send("#{att}=".to_sym, value)
            end

            check_errors_on_save(notification_rule)

            notification_rule.to_json
          end

          # Deletes a notification rule
          # https://github.com/flpjck/flapjack/wiki/API#wiki-put_notification_rules_id
          app.delete('/notification_rules/:id') do
            logger.debug("delete /notification_rules/#{params[:id]}")
            rule = find_rule(params[:id])
            contact = rule.contact
            halt err(404, "no contact") if contact.nil?
            logger.debug("rule to delete: #{rule.inspect}, contact: #{contact.inspect}")
            contact.notification_rules.delete(rule)
            rule.destroy
            status 204
          end

          # Returns the media of a contact
          # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts_id_media
          app.get '/contacts/:contact_id/media' do
            content_type :json

            find_contact(params[:contact_id]).media.to_json
          end

          # Returns the specified media of a contact
          # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts_id_media_media
          app.get('/contacts/:contact_id/media/:id') do
            content_type :json

            medium = find_contact(params[:contact_id]).media.intersect(:type => params[:id]).all.first
            if medium.nil?
              halt err(403, "no #{params[:id]} for contact '#{params[:contact_id]}'")
            end
            medium.to_json
          end

          # Creates or updates a media of a contact
          # https://github.com/flpjck/flapjack/wiki/API#wiki-put_contacts_id_media_media
          app.put('/contacts/:contact_id/media/:id') do
            content_type :json

            contact = find_contact(params[:contact_id])
            media = contact.media

            medium = media.intersect(:type => params[:id]).all.first
            is_new = false
            if medium.nil?
              medium = Flapjack::Data::Medium.new(:type => params[:id])
              is_new = true
            end
            medium.address = params[:address]
            [:interval, :rollup_threshold].each do |att|
              next unless params[att]
              medium.send("#{att}=".to_sym, params[att].to_i)
            end
            check_errors_on_save(medium)
            media << medium if is_new

            medium.to_json
          end

          # delete a media of a contact
          app.delete('/contacts/:contact_id/media/:id') do
            contact = find_contact(params[:contact_id])

            media = contact.media

            unless medium = media.intersect(:type => params[:id]).all.first
              halt err(404, ["No media found with type '#{params[:id]}' for contact '#{params[:contact_id]}'"])
            end

            media.delete(medium)
            medium.destroy
            status 204
          end

          # Returns the timezone of a contact
          # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts_id_timezone
          app.get('/contacts/:contact_id/timezone') do
            content_type :json

            contact = find_contact(params[:contact_id])
            contact.timezone.name.to_json
          end

          # Sets the timezone of a contact
          # https://github.com/flpjck/flapjack/wiki/API#wiki-put_contacts_id_timezone
          app.put('/contacts/:contact_id/timezone') do
            content_type :json

            contact = find_contact(params[:contact_id])
            contact.timezone = params[:timezone]
            check_errors_on_save(contact)

            contact.timezone.name.to_json
          end

          # Removes the timezone of a contact
          # https://github.com/flpjck/flapjack/wiki/API#wiki-put_contacts_id_timezone
          app.delete('/contacts/:contact_id/timezone') do
            contact = find_contact(params[:contact_id])
            contact.timezone = nil
            contact.save
            status 204
          end

          app.post '/contacts/:contact_id/tags' do
            content_type :json

            tags = find_contact_tags(params[:tag])
            contact = find_contact(params[:contact_id])
            contact.tags += tags
            contact.save
            contact.tags.to_json
          end

          app.post '/contacts/:contact_id/entity_tags' do
            content_type :json
            contact = find_contact(params[:contact_id])
            entities = contact.entities

            entities.each do |entity|
              next unless ent_tags = params[:entity][entity.name]
              entity.tags += ent_tags
            end

            contact_ent_tag = hashify(*entities.all) {|entity|
              [entity.name, entity.tags]
            }

            contact_ent_tag.to_json
          end

          app.delete '/contacts/:contact_id/tags' do
            tags = find_contact_tags(params[:tag])
            contact = find_contact(params[:contact_id])
            contact.tags -= tags
            contact.save
            status 204
          end

          app.delete '/contacts/:contact_id/entity_tags' do
            contact = find_contact(params[:contact_id])

            contact.entities.each do |entity|
              next unless ent_tags = params[:entity][entity.name]
              entity.tags -= ent_tags
            end

            status 204
          end

          app.get '/contacts/:contact_id/tags' do
            content_type :json

            contact = find_contact(params[:contact_id])
            contact.tags.to_json
          end

          app.get '/contacts/:contact_id/entity_tags' do
            content_type :json

            contact = find_contact(params[:contact_id])
            contact_ent_tag = hashify(*contact.entities.all) {|entity|
              [entity.name, entity.tags]
            }
            contact_ent_tag.to_json
          end

        end

      end

    end

  end

end
