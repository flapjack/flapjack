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

          def find_contact(contact_id)
            contact = Flapjack::Data::Contact.find_by_id(contact_id)
            raise Flapjack::Gateways::JSONAPI::ContactNotFound.new(contact_id) if contact.nil?
            contact
          end

          def find_rule(rule_id)
            rule = Flapjack::Data::NotificationRule.find_by_id(rule_id)
            raise Flapjack::Gateways::JSONAPI::NotificationRuleNotFound.new(rule_id) if rule.nil?
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

          def populate_contact(contact, contact_data)
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

        def self.registered(app)

          app.helpers Flapjack::Gateways::JSONAPI::ContactMethods::Helpers

          app.post '/contacts' do
            pass unless Flapjack::Gateways::JSONAPI::JSON_REQUEST_MIME_TYPES.include?(request.content_type)
            content_type :json
            cors_headers

            contacts_data = params[:contacts]

            if contacts_data.nil? || !contacts_data.is_a?(Enumerable)
              halt err(422, "No valid contacts were submitted")
            end

            contacts_ids = contacts_data.reject {|c| c['id'].nil? }.
              map {|co| co['id'].to_s }

            Flapjack::Data::Contact.send(:lock, Flapjack::Data::Medium) do

              conflicted_ids = contacts_ids.select {|id|
                Flapjack::Data::Contact.exists?(id)
              }

              if conflicted_ids.size > 0
                halt err(409, "Contacts already exist with the following IDs: " +
                  conflicted_ids.join(', '))
              else
                contacts_data.each do |contact_data|
                  unless contact_data['id']
                    contact_data['id'] = SecureRandom.uuid
                  end

                  contact = Flapjack::Data::Contact.new(:id => contact_data['id'].to_s)
                  populate_contact(contact, contact_data)
                end
              end

            end

            ids = contacts_data.map {|c| c['id']}
            location(ids)

            contacts_data.map {|cd| cd['id']}.to_json
          end

          app.post '/contacts_atomic' do
            pass unless Flapjack::Gateways::JSONAPI::JSON_REQUEST_MIME_TYPES.include?(request.content_type)
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
                Flapjack::Data::Contact.send(:lock, Flapjack::Data::Medium) do
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
                    populate_contact(contact, contact_data)
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
            cors_headers

            contacts = if params[:ids]
              Flapjack::Data::Contact.find_by_ids(params[:ids].split(',').uniq)
            else
              Flapjack::Data::Contact.all
            end
            contacts.compact!

            linked_entity_data, linked_entity_ids = if contacts.empty?
              [[], []]
            else
              Flapjack::Data::Contact.entities_jsonapi(contacts.map(&:id))
            end

            contacts_json = contacts.collect {|contact|
              contact.linked_entity_ids = linked_entity_ids[contact.id]
              contact.to_json
            }.join(", ")

            '{"contacts":[' + contacts_json + ']' +
              ( linked_entity_data.empty? ? '}' :
                ', "linked": {"entities":' + linked_entity_data.to_json + '}}')
          end

          # Returns the core information about the specified contact
          # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts_id
          app.get '/contacts/:contact_id' do
            content_type :json
            cors_headers
            contact = find_contact(params[:contact_id])

            entities = contact.entities.map {|e| e[:entity] }

            '{"contacts":[' + contact.to_json + ']' +
              ( entities.empty? ? '}' :
                ', "linked": {"entities":' + entities.values.to_json + '}}')
          end

          # Updates a contact
          app.put '/contacts/:contact_id' do
            content_type :json
            cors_headers

            contacts_data = params[:contacts]

            if contacts_data.nil? || !contacts_data.is_a?(Enumerable)
              halt err(422, "No valid contacts were submitted")
            end

            unless contacts_data.length == 1
              halt err(422, "Exactly one contact hash must be supplied.")
            end

            contact_data = contacts_data.first

            if contact_data['id'] && contact_data['id'].to_s != params[:contact_id]
              halt err(422, "ID, if supplied, must match URL")
            end

            contact = find_contact(params[:contact_id])
            #contact_data = hashify('first_name', 'last_name', 'email', 'media', 'tags') {|k| [k, params[k]]}
            logger.debug("contact_data: #{contact_data}")
            contact.update(contact_data)

            contact.to_json
          end

          # Deletes a contact
          app.delete '/contacts/:contact_id' do
            cors_headers
            Flapjack::Data::Contact.send(:lock, Flapjack::Data::Medium,
              Flapjack::Data::NotificationRule,
              Flapjack::Data::NotificationRuleState) do
              contact = find_contact(params[:contact_id])
              contact.delete!
            end
            status 204
          end

          # Lists this contact's notification rules
          # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts_id_notification_rules
          app.get '/contacts/:contact_id/notification_rules' do
            content_type :json
            cors_headers

            "[" + find_contact(params[:contact_id]).notification_rules.map {|r| r.to_json }.join(',') + "]"
          end

          # Get the specified notification rule for this user
          # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts_id_notification_rules_id
          app.get '/notification_rules/:id' do
            content_type :json
            cors_headers

            '{"notification_rules":[' +
              find_rule(params[:id]).to_json +
              ']}'
          end

          # Creates a notification rule or rules for a contact
          # https://github.com/flpjck/flapjack/wiki/API#wiki-post_contacts_id_notification_rules
          app.post '/notification_rules' do
            content_type :json
            cors_headers

            contact = find_contact(params[:contact_id])

            rules_data = params[:notification_rules]

            if rules_data.nil? || !rules_data.is_a?(Enumerable)
              halt err(422, "No valid notification rules were submitted")
            end

            if rules_data.any? {|rule| rule['id']}
              halt err(422, "ID fields may not be generated by you. Remove IDs and POST again")
            end

            states = {}
            state_media = {}

            notification_rules = rules_data.collect do |rule_data|
              tag_data = case rule_data['tags']
              when Array
                Set.new(rule_data['tags'])
              when String
                Set.new([rule_data['tags']])
              else
                Set.new
              end

              rule = Flapjack::Data::NotificationRule.new(
                :entities           => rule_data['entities'],
                :tags               => tag_data,
                :time_restrictions  => rule_data['time_restrictions'])

              states[rule.object_id] = Flapjack::Data::CheckState.failing_states.collect do |fail_state|

                state = Flapjack::Data::NotificationRuleState.new(:state => fail_state,
                  :blackhole => !!rule_data["#{fail_state}_blackhole"])

                state_media[state.object_id] = []

                media_types = rule_data["#{fail_state}_media"]
                unless media_types.nil? || media_types.empty?
                  media_for_state = contact.media.intersect(:type => media_types).all
                  state_media[state.object_id] += media_for_state
                end

                state
              end

              rule
            end

            errors = notification_rules.inject([]) do |memo, notification_rule|
              memo += notification_rule.errors.full_messages unless notification_rule.valid?
              memo
            end

            halt err(422, *errors) unless errors.empty?

            notification_rules.each do |notification_rule|

              notification_rule.save
              states[notification_rule.object_id].each do |state|
                state.save
                state.media.add(*state_media[state.object_id])
              end

              notification_rule.states.add(*states.values.flatten(1))

              contact.notification_rules << notification_rule
            end

            ids = notification_rules.map {|r| r.id}
            location(ids)

            notification_rules_json = notification_rules.collect {|notification_rule|
              notification_rule.to_json
            }.join(", ")

            '{"notification_rules":[' + notification_rules_json + ']}'
          end

          # Updates a notification rule
          # https://github.com/flpjck/flapjack/wiki/API#wiki-put_notification_rules_id
          app.put('/notification_rules/:id') do
            content_type :json
            cors_headers

            rules_data = params[:notification_rules]

            if rules_data.nil? || !rules_data.is_a?(Enumerable)
              halt err(422, "No valid notification rules were submitted")
            end

            unless rules_data.length == 1
              halt err(422, "Exactly one notification rules hash must be supplied.")
            end

            rule_data = rules_data.first

            if rule_data['id'] && rule_data['id'].to_s != params[:id]
              halt err(422, "ID, if supplied, must match URL")
            end

            notification_rule = find_rule(params[:id])
            contact = notification_rule.contact
            halt err(404, "Notification rule #{notification_rule.id} has no contact") if contact.nil?

            supplied_contact_id = rule_data.delete('contact_id')
            if supplied_contact_id && supplied_contact_id != contact.id
              halt err(422, "contact_id cannot be modified")
            end

            tag_data = case rule_data['tags']
            when Array
              Set.new(rule_data['tags'])
            when String
              Set.new([rule_data['tags']])
            else
              Set.new
            end

            {:entities           => rule_data['entities'],
             :tags               => tag_data,
             :time_restrictions  => rule_data['time_restrictions']}.each_pair do |att, value|

              notification_rule.send("#{att}=".to_sym, value)
            end

            check_errors_on_save(notification_rule)

            Flapjack::Data::CheckState.failing_states.each do |fail_state|
              next unless rule_data.has_key?("#{fail_state}_blackhole") ||
                rule_data.has_key?("#{fail_state}_media")

              state = notification_rule.states.intersect(:state => fail_state).all.first ||
                        Flapjack::Data::NotificationRuleState.new(:state => fail_state)

              state.blackhole = !!rule_data.has_key?("#{fail_state}_blackhole".to_sym)
              state.save

              media_types = rule_data["#{fail_state}_media".to_sym]
              unless media_types.nil? || media_types.empty?
                state_media = contact.media.intersect(:type => media_types).all
                state.media.add(*state_media) unless state_media.empty?
              end
            end

            '{"notification_rules":[' +
              notification_rule.to_json +
              ']}'
          end

          # Deletes a notification rule
          # https://github.com/flpjck/flapjack/wiki/API#wiki-put_notification_rules_id
          app.delete('/notification_rules/:id') do
            cors_headers
            rule = find_rule(params[:id])
            logger.debug("rule to delete: #{rule.inspect}, contact_id: #{rule.contact_id}")
            contact = rule.contact
            halt err(404, "Notification rule #{rule.id} has no contact") if contact.nil?
            contact.notification_rules.delete(rule)
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
