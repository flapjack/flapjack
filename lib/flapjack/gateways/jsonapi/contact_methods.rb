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

          def find_contact(contact_id)
            contact = Flapjack::Data::Contact.find_by_id(contact_id, :logger => logger, :redis => redis)
            raise Flapjack::Gateways::JSONAPI::ContactNotFound.new(contact_id) if contact.nil?
            contact
          end

          def find_rule(rule_id)
            rule = Flapjack::Data::NotificationRule.find_by_id(rule_id, :logger => logger, :redis => redis)
            raise Flapjack::Gateways::JSONAPI::NotificationRuleNotFound.new(rule_id) if rule.nil?
            rule
          end

          def find_tags(tags)
            halt err(400, "no tags given") if tags.nil? || tags.empty?
            tags
          end

          def obtain_semaphore(resource)
            semaphore = nil
            strikes = 0
            begin
              semaphore = Flapjack::Data::Semaphore.new(resource, {:redis => redis, :expiry => 30})
            rescue Flapjack::Data::Semaphore::ResourceLocked
              strikes += 1
              raise Flapjack::Gateways::JSONAPI::ResourceLocked.new(resource) unless strikes < 3
              sleep 1
              retry
            end
            raise Flapjack::Gateways::JSONAPI::ResourceLocked.new(resource) unless semaphore
            semaphore
          end

          def apply_json_patch(object_path, &block)
            ops = params[:ops]

            if ops.nil? || !ops.is_a?(Array)
              halt err(400, "Invalid JSON-Patch request")
            end

            ops.each do |operation|
              linked = nil
              property = nil

              op = operation['op']
              operation['path'] =~ /\A\/#{object_path}\/0\/([^\/]+)(?:\/([^\/]+)(?:\/([^\/]+))?)?\z/
              if 'links'.eql?($1)
                linked = $2

                value = case op
                when 'add'
                  operation['value']
                when 'remove'
                  $3
                end
              elsif 'replace'.eql?(op)
                property = $1
                value = $3
              else
                next
              end

              yield(op, property, linked, value)
            end
          end

        end

        def self.registered(app)

          app.helpers Flapjack::Gateways::JSONAPI::ContactMethods::Helpers

          app.post '/contacts' do
            pass unless is_json_request?
            content_type :json
            cors_headers

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


          # Returns all (/contacts) or some (/contacts/1,2,3) or one (/contact/2) contact(s)
          # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts
          app.get %r{/contacts(?:/)?([^/]+)?$} do
            content_type 'application/vnd.api+json'
            cors_headers

            requested_contacts = if params[:captures] && params[:captures][0]
              params[:captures][0].split(',').uniq
            else
              nil
            end

            #FIXME: do we need to url decode the ids? has rack or some middleware already done this?
            contacts = if requested_contacts
              Flapjack::Data::Contact.find_by_ids(requested_contacts, :logger => logger, :redis => redis)
            else
              Flapjack::Data::Contact.all(:redis => redis)
            end
            contacts.compact!

            if requested_contacts && contacts.empty?
              raise Flapjack::Gateways::JSONAPI::ContactsNotFound.new(requested_contacts)
            end

            linked_entity_data, linked_entity_ids = if contacts.empty?
              [[], []]
            else
              Flapjack::Data::Contact.entities_jsonapi(contacts.map(&:id), :redis => redis)
            end

            linked_media_data = []
            linked_media_ids  = {}
            contacts.each do |contact|
              contact.media.keys.each do |medium|
                id = "#{contact.id}_#{medium}"
                interval = contact.media_intervals[medium].nil? ? nil : contact.media_intervals[medium].to_i
                rollup_threshold = contact.media_rollup_thresholds[medium].nil? ? nil : contact.media_rollup_thresholds[medium].to_i
                linked_media_ids[contact.id] = id
                linked_media_data <<
                  { "id" => id,
                    "type" => medium,
                    "address" => contact.media[medium],
                    "interval" => interval,
                    "rollup_threshold" => rollup_threshold,
                    "contact_id" => contact.id }
              end
            end

            contacts_json = contacts.collect {|contact|
              contact.linked_entity_ids = linked_entity_ids[contact.id]
              contact.linked_media_ids  = linked_media_ids[contact.id]
              contact.to_jsonapi
            }.join(", ")

            '{"contacts":[' + contacts_json + ']' +
                ',"linked":{"entities":' + linked_entity_data.to_json +
                          ',"media":' + linked_media_data.to_json + '}}'
          end

          # Returns the core information about the specified contact
          # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts_id
          app.get '/contacts/:contact_id' do
            content_type 'application/vnd.api+json'
            cors_headers
            contact = find_contact(params[:contact_id])

            entities = contact.entities.map {|e| e[:entity] }

            '{"contacts":[' + contact.to_jsonapi + ']' +
              ( entities.empty? ? '}' :
                ', "linked": {"entities":' + entities.values.to_json + '}}')
          end

          # Updates a contact
          app.put '/contacts/:contact_id' do
            cors_headers
            content_type :json

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

            contact.to_jsonapi
          end

          # TODO this should build up all data, verify entities exist, etc.
          # before applying any changes
          # TODO generalise JSON-Patch data parsing code
          app.patch '/contacts/:contact_id' do
            pass unless is_jsonpatch_request?
            content_type :json
            cors_headers

            contact = find_contact(params[:contact_id])

            apply_json_patch('contacts') do |op, property, linked, value|
              case op
              when 'replace'
                if ['first_name', 'last_name', 'email'].include?(property)
                  contact.update(property => value)
                end
              when 'add'
                if 'entities'.eql?(linked)
                  entity = Flapjack::Data::Entity.find_by_id(value, :redis => redis)
                  contact.add_entity(entity) unless entity.nil?
                end
              when 'remove'
                if 'entities'.eql?(linked)
                  entity = Flapjack::Data::Entity.find_by_id(value, :redis => redis)
                  contact.remove_entity(entity) unless entity.nil?
                end
              end
            end

            # will need to be 200 and return contact.to_jsonapi
            # if updated_at changes, or Etag, when those are introduced
            status 204
          end

          # Deletes a contact
          app.delete '/contacts/:contact_id' do
            cors_headers
            semaphore = obtain_semaphore(SEMAPHORE_CONTACT_MASS_UPDATE)
            contact = find_contact(params[:contact_id])
            contact.delete!
            semaphore.release
            status 204
          end

          app.post '/media' do
            pass unless is_json_request?
            content_type :json
            cors_headers

            media_data = params[:media]

            if media_data.nil? || !media_data.is_a?(Enumerable)
              halt err(422, "No valid media were submitted")
            end

            unless media_data.all? {|m| m['id'].nil? }
              halt err(422, "Media creation cannot include IDs")
            end

            semaphore = obtain_semaphore(SEMAPHORE_CONTACT_MASS_UPDATE)

            contacts = media_data.inject({}) {|memo, medium_data|
              contact_id = medium_data['contact_id']
              if contact_id.nil?
                semaphore.release
                halt err(422, "Media data must include 'contact_id'")
              end
              next memo if memo.has_key?(contact_id)
              contact = Flapjack::Data::Contact.find_by_id(contact_id, :redis => redis)
              if contact.nil?
                semaphore.release
                halt err(422, "Contact id:'#{contact_id}' could not be loaded")
              end
              memo[contact_id] = contact
              memo
            }

            media_data.each do |medium_data|
              contact = contacts[medium_data['contact_id']]
              type = medium_data['type']
              contact.set_address_for_media(type, medium_data['address'])
              contact.set_interval_for_media(type, medium_data['interval'])
              contact.set_rollup_threshold_for_media(type, medium_data['rollup_threshold'])
              medium_data['id'] = "#{contact.id}_#{type}"
            end

            semaphore.release

            '{"media":' + media_data.to_json + '}'
          end

          app.patch '/media/:media_id' do
            pass unless is_jsonpatch_request?
            content_type :json
            cors_headers

            media_id = params[:media_id]
            media_id =~ /\A(.+)_(email|sms|jabber)\z/

            contact_id = $1
            type = $2

            halt err(422, "Could not get contact_id from media_id") if contact_id.nil?
            halt err(422, "Could not get type from media_id") if type.nil?

            contact = find_contact(contact_id)

            apply_json_patch('media') do |op, property, linked, value|
              if 'replace'.eql?(op)
                case property
                when 'address'
                  contact.set_address_for_media(type, value)
                when 'interval'
                  contact.set_interval_for_media(type, value)
                when 'rollup_threshold'
                  contact.set_rollup_threshold_for_media(type, value)
                end
              end
            end

            status 204
          end

          app.get '/notification_rules/:id' do
            content_type :json
            cors_headers

            '{"notification_rules":[' +
              find_rule(params[:id]).to_json +
              ']}'
          end

          # Creates a notification rule or rules for a contact
          app.post '/notification_rules' do
            content_type :json
            cors_headers

            rules_data = params[:notification_rules]

            if rules_data.nil? || !rules_data.is_a?(Enumerable)
              halt err(422, "No valid notification rules were submitted")
            end

            if rules_data.any? {|rule| rule['id']}
              halt err(422, "ID fields may not be generated by you. Remove IDs and POST again")
            end

            errors = []
            rules_data.each do |rule_data|
              errors << Flapjack::Data::NotificationRule.prevalidate_data(symbolize(rule_data), {:logger => logger})
            end
            errors.compact!

            unless errors.nil? || errors.empty?
              halt err(422, *errors)
            end

            rules = []
            errors = []
            rules_data.each do |rule_data|
              rule_data = symbolize(rule_data)
              contact   = find_contact(rule_data.delete(:contact_id))
              rule_or_errors = contact.add_notification_rule(rule_data, :logger => logger)
              if rule_or_errors.respond_to?(:critical_media)
                rules << rule_or_errors
              else
                errors << rule_or_errors
              end
            end

            if rules.empty?
              halt err(422, *errors)
            else
              if errors.empty?
                status 201
              else
                logger.warn("Errors during bulk notification rules creation: " + errors.join(', '))
                status 200
              end
            end
            ids = rules.map {|r| r.id}
            location(ids)
            '{"notification_rules":[' +
              rules.map {|r| r.to_json}.join(',') +
              ']}'
          end

          # Updates a notification rule
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

            rule = find_rule(params[:id])
            contact = find_contact(rule.contact_id)

            supplied_contact = rule_data.delete('contact_id')
            if supplied_contact && supplied_contact != contact.id
              halt err(422, "contact_id cannot be modified")
            end

            errors = rule.update(symbolize(rule_data), :logger => logger)

            unless errors.nil? || errors.empty?
              halt err(422, *errors)
            end
            '{"notification_rules":[' +
              rule.to_json +
              ']}'
          end

          # Deletes a notification rule
          app.delete('/notification_rules/:id') do
            cors_headers
            rule = find_rule(params[:id])
            logger.debug("rule to delete: #{rule.inspect}, contact_id: #{rule.contact_id}")
            contact = find_contact(rule.contact_id)
            contact.delete_notification_rule(rule)
            status 204
          end

        end

      end

    end

  end

end
