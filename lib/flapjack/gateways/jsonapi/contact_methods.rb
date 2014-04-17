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

          def split_media_ids(media_id)
            media_ids = media_id.split(',')

            media_ids.collect do |m_id|
              m_id =~ /\A(.+)_(email|sms|jabber)\z/

              contact_id = $1
              media_type = $2
              halt err(422, "Could not get contact_id from media_id") if contact_id.nil?
              halt err(422, "Could not get media type from media_id") if media_type.nil?

              {:contact => find_contact(contact_id), :type => media_type}
            end
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

          # TODO this should build up all data, verify entities exist, etc.
          # before applying any changes
          # TODO generalise JSON-Patch data parsing code
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
                    logger.debug "patch add operation. linked: #{linked}"
                    if 'entities'.eql?(linked)
                      entity = Flapjack::Data::Entity.find_by_id(value, :redis => redis)
                      logger.debug "adding this entity: #{entity}"
                      contact.add_entity(entity) unless entity.nil?
                    end
                  when 'remove'
                    if 'entities'.eql?(linked)
                      entity = Flapjack::Data::Entity.find_by_id(value, :redis => redis)
                      contact.remove_entity(entity) unless entity.nil?
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

          # Creates media records for a contact
          app.post '/contacts/:contact_id/media' do
            media_data = params[:media]

            if media_data.nil? || !media_data.is_a?(Enumerable)
              halt err(422, "No valid media were submitted")
            end

            unless media_data.all? {|m| m['id'].nil? }
              halt err(422, "Media creation cannot include IDs")
            end

            semaphore = obtain_semaphore(SEMAPHORE_CONTACT_MASS_UPDATE)
            contact = Flapjack::Data::Contact.find_by_id(params[:contact_id], :redis => redis)
            if contact.nil?
              semaphore.release
              halt err(422, "Contact id:'#{contact_id}' could not be loaded")
            end

            media_data.each do |medium_data|
              type = medium_data['type']
              contact.set_address_for_media(type, medium_data['address'])
              contact.set_interval_for_media(type, medium_data['interval'])
              contact.set_rollup_threshold_for_media(type, medium_data['rollup_threshold'])
              medium_data['id'] = "#{contact.id}_#{type}"
            end

            semaphore.release

            '{"media":' + media_data.to_json + '}'
          end

          # get one or more media records; media ids are, for Flapjack
          # v1, composed of "#{contact.id}_#{media_type}"
          app.get '/media/:media_id' do
            contact_media = split_media_ids(params[:media_id])

            media_data = contact_media.inject([]) do |memo, (contact, media_type)|
              medium_id = "#{contact.id}_#{media_type}"
              data = if 'pagerduty'.eql?(media_type)
                contact.pagerduty_credentials
              else
                {:address          => contact.media[media_type],
                 :interval         => contact.media_intervals[media_type],
                 :rollup_threshold => contact.media_rollup_thresholds[media_type] }
              end

              memo[medium_id] = data.merge(:id => medium_id, :type => media_type,
                :links => {:contacts => [contact.id]})

              memo
            end

            '{"media":' + media_data.to_json + '}'
          end

          # update one or more media records; media ids are, for Flapjack
          # v1, composed of "#{contact.id}_#{media_type}"
          app.patch '/media/:media_id' do
            contact_media = split_media_ids(params[:media_id])

            contact_media.each_pair do |contact, media_type|
              apply_json_patch('media') do |op, property, linked, value|
                if 'replace'.eql?(op)
                  case property
                  when 'address'
                    contact.set_address_for_media(media_type, value)
                  when 'interval'
                    contact.set_interval_for_media(media_type, value)
                  when 'rollup_threshold'
                    contact.set_rollup_threshold_for_media(media_type, value)
                  end
                end
              end
            end

            status 204
          end

          # delete one or more media records; media ids are, for Flapjack
          # v1, composed of "#{contact.id}_#{media_type}"
          app.delete '/media/:media_id' do
            contact_media = split_media_ids(params[:media_id])
            contact_media.each_pair do |contact, media_type|
              contact.remove_media(media_type)
            end
            status 204
          end

          # get one or more notification rules
          app.get '/notification_rules/:id' do
            rules_json = params[:id].split(',').collect {|rule_id|
              find_rule(rule_id).to_jsonapi
            }.join(', ')

            '{"notification_rules":[' + rules_json + ']}'
          end

          # Creates a notification rule or rules for a contact
          app.post '/contacts/:contact_id/notification_rules' do
            rules_data = params[:notification_rules]

            if rules_data.nil? || !rules_data.is_a?(Enumerable)
              halt err(422, "No valid notification rules were submitted")
            end

            contact = find_contact(params[:contact_id])

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

            rules_json = rules.map {|r| r.to_json}.join(',')
            '{"notification_rules":[' + rules_json + ']}'
          end

          # Updates one or more notification rules
          app.put '/notification_rules/:id' do
            rules_data = params[:notification_rules]

            if rules_data.nil? || !rules_data.is_a?(Enumerable)
              halt err(422, "No valid notification rules were submitted")
            end

            rule_ids       = params[:id].split(',')
            rules_data_ids = rules_data.collect {|rd| rd['id'].to_s }

            unless (rule_ids & rules_data_ids) == rule_ids
              halt err(422, "Rule id parameters do not match rule update data ids")
            end

            # pre-retrieve rule objects, errors before data is changed if any
            # are not found
            rules      = rule_ids.collect {|rule_id| find_rule(rule_id) }
            rules_json = rules.inject([]) {|memo, rule|
              if rule_data = rules_data.detect {|rd| rd['id'].to_s == rule.id}
                rule.update(symbolize(rule_data), :logger => logger)
                memo << rule.to_json
              end
              memo
            }.join(', ')

            '{"notification_rules":[' + rules_json + ']}'
          end

          # Deletes one or more notification rules
          app.delete '/notification_rules/:id' do
            params[:id].split(',').each do |rule_id|
              rule = find_rule(rule_id)
              logger.debug("rule to delete: #{rule.inspect}, contact_id: #{rule.contact_id}")
              contact = find_contact(rule.contact_id)
              contact.delete_notification_rule(rule)
            end

            status 204
          end

        end

      end

    end

  end

end
