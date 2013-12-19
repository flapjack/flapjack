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

      class NotificationRuleNotFound < RuntimeError
        attr_reader :rule_id
        def initialize(rule_id)
          @rule_id = rule_id
        end
      end

      module ContactMethods

        module Helpers

          def find_contact(contact_id)
            contact = Flapjack::Data::Contact.find_by_id(contact_id, :logger => logger, :redis => redis)
            raise Flapjack::Gateways::API::ContactNotFound.new(contact_id) if contact.nil?
            contact
          end

          def find_rule(rule_id)
            rule = Flapjack::Data::NotificationRule.find_by_id(rule_id, :logger => logger, :redis => redis)
            raise Flapjack::Gateways::API::NotificationRuleNotFound.new(rule_id) if rule.nil?
            rule
          end

          def find_tags(tags)
            halt err(400, "no tags given") if tags.nil? || tags.empty?
            tags
          end

        end

        def self.registered(app)

          app.helpers Flapjack::Gateways::API::ContactMethods::Helpers

          app.post '/contacts' do
            pass unless 'application/json'.eql?(request.content_type)
            content_type :json

            contacts_data = params[:contacts]

            #TODO: add lock around all create / delete operations against contacts

            if contacts_data.nil? || !contacts_data.is_a?(Enumerable)
              # https://tools.ietf.org/html/rfc2616#section-10.4.1
              halt err(422, "No valid contacts were submitted")
            end

            contacts_ids = contacts_data.reject {|c| c['id'].nil? }.
              map {|co| co['id'].to_s }

            conflicted_ids = contacts_ids.find_all {|id|
              Flapjack::Data::Contact.exists_with_id?(id, :redis => redis)
            }

            unless conflicted_ids.empty?
              # https://tools.ietf.org/html/rfc2616#section-10.4.10
              halt err(409, "Contacts already exist with the following IDs: " +
                conflicted_ids.join(', '))
            end

            contacts_data.each do |contact_data|
              unless contact_data['id']
                contact_data['id'] = SecureRandom.uuid
              end
              Flapjack::Data::Contact.add(contact_data, :redis => redis)
            end

            logger.debug("post /contacts data: ")
            logger.debug(params.inspect)

            contacts_data.map {|cd| cd['id']}.to_json
          end

          app.post '/contacts_atomic' do
            pass unless 'application/json'.eql?(request.content_type)
            content_type :json

            contacts_data = params[:contacts]
            if contacts_data.nil? || !contacts_data.is_a?(Enumerable)
              halt err(422, "No valid contacts were submitted")
            end

            # stringifying as integer string params are automatically integered,
            # but our redis ids are strings
            contacts_data_ids = contacts_data.reject {|c| c['id'].nil? }.
              map {|co| co['id'].to_s }

            if contacts_data_ids.empty?
              halt err(422, "No contacts with IDs were submitted")
            end

            contacts = Flapjack::Data::Contact.all(:redis => redis)
            contacts_h = hashify(*contacts) {|c| [c.id, c] }
            contacts_ids = contacts_h.keys

            # delete contacts not found in the bulk list
            (contacts_ids - contacts_data_ids).each do |contact_to_delete_id|
              contact_to_delete = contacts.detect {|c| c.id == contact_to_delete_id }
              contact_to_delete.delete!
            end

            # add or update contacts found in the bulk list
            contacts_data.reject {|cd| cd['id'].nil? }.each do |contact_data|
              if contacts_ids.include?(contact_data['id'].to_s)
                contacts_h[contact_data['id'].to_s].update(contact_data)
              else
                Flapjack::Data::Contact.add(contact_data, :redis => redis)
              end
            end
            204
          end

          # Returns all the contacts
          # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts
          app.get '/contacts' do
            content_type :json
            "[" +
              Flapjack::Data::Contact.all(:redis => redis).map do |contact|
                contact.to_json
              end.join(',') +
              "]"
          end

          # Returns the core information about the specified contact
          # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts_id
          app.get '/contacts/:contact_id' do
            content_type :json

            contact = find_contact(params[:contact_id])
            contact.to_json
          end

          # Updates a contact
          app.put '/contacts/:contact_id' do
            content_type :json

            if params['id']
              halt err(422, "ID must not be supplied")
            end

            contact = find_contact(params[:contact_id])
            contact_data = hashify(:first_name, :last_name, :email, :media, :tags) {|k| [k, params[k]]}

            contact.update(contact_data)
            contact.to_json
          end

          # Lists this contact's notification rules
          # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts_id_notification_rules
          app.get '/contacts/:contact_id/notification_rules' do
            content_type :json

            "[" + find_contact(params[:contact_id]).notification_rules.map {|r| r.to_json }.join(',') + "]"
          end

          # Get the specified notification rule for this user
          # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts_id_notification_rules_id
          app.get '/notification_rules/:id' do
            content_type :json

            rule = find_rule(params[:id])
            rule.to_json
          end

          # Creates a notification rule for a contact
          # https://github.com/flpjck/flapjack/wiki/API#wiki-post_contacts_id_notification_rules
          app.post '/notification_rules' do
            content_type :json

            if params[:id]
              halt err(422, "post cannot be used for update, do a put instead, or remove id")
            end

            logger.debug("post /notification_rules data: ")
            logger.debug(params.inspect)

            contact = find_contact(params[:contact_id])

            rule_data = hashify(:entities, :tags,
              :unknown_media, :warning_media, :critical_media, :time_restrictions,
              :unknown_blackhole, :warning_blackhole, :critical_blackhole) {|k| [k, params[k]]}

            rule_or_errors = contact.add_notification_rule(rule_data, :logger => logger)

            unless rule_or_errors.respond_to?(:critical_media)
              halt err(422, *rule_or_errors)
            end
            rule_or_errors.to_json
          end

          # Updates a notification rule
          # https://github.com/flpjck/flapjack/wiki/API#wiki-put_notification_rules_id
          app.put('/notification_rules/:id') do
            content_type :json

            rule = find_rule(params[:id])
            contact = find_contact(rule.contact_id)

            rule_data = hashify(:entities, :tags,
              :unknown_media, :warning_media, :critical_media, :time_restrictions,
              :unknown_blackhole, :warning_blackhole, :critical_blackhole) {|k| [k, params[k]]}

            errors = rule.update(rule_data, :logger => logger)

            unless errors.nil? || errors.empty?
              halt err(422, *errors)
            end
            rule.to_json
          end

          # Deletes a notification rule
          # https://github.com/flpjck/flapjack/wiki/API#wiki-put_notification_rules_id
          app.delete('/notification_rules/:id') do
            logger.debug("delete /notification_rules/#{params[:id]}")
            rule = find_rule(params[:id])
            logger.debug("rule to delete: #{rule.inspect}, contact_id: #{rule.contact_id}")
            contact = find_contact(rule.contact_id)
            contact.delete_notification_rule(rule)
            status 204
          end

          # Returns the media of a contact
          # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts_id_media
          app.get '/contacts/:contact_id/media' do
            content_type :json

            contact = find_contact(params[:contact_id])

            media = contact.media
            media_intervals = contact.media_intervals
            media_rollup_thresholds = contact.media_rollup_thresholds
            media_addr_int = hashify(*media.keys) {|k|
              [k, {'address'          => media[k],
                   'interval'         => media_intervals[k],
                   'rollup_threshold' => media_rollup_thresholds[k] }]
            }
            media_addr_int.to_json
          end

          # Returns the specified media of a contact
          # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts_id_media_media
          app.get('/contacts/:contact_id/media/:id') do
            content_type :json

            contact = find_contact(params[:contact_id])
            media = contact.media[params[:id]]
            if media.nil?
              halt err(404, "no #{params[:id]} for contact '#{params[:contact_id]}'")
            end
            interval = contact.media_intervals[params[:id]]
            # FIXME: does erroring when no interval found make sense?
            if interval.nil?
              halt err(403, "no #{params[:id]} interval for contact '#{params[:contact_id]}'")
            end
            rollup_threshold = contact.media_rollup_thresholds[params[:id]]
            {'address'          => media,
             'interval'         => interval,
             'rollup_threshold' => rollup_threshold }.to_json
          end

          # Creates or updates a media of a contact
          # https://github.com/flpjck/flapjack/wiki/API#wiki-put_contacts_id_media_media
          app.put('/contacts/:contact_id/media/:id') do
            content_type :json

            contact = find_contact(params[:contact_id])
            errors = []

            if 'pagerduty'.eql?(params[:id])
              errors = [:service_key, :subdomain, :username, :password].inject([]) do |memo, pdp|
                memo << "no #{pdp.to_s} for 'pagerduty' media" if params[pdp].nil?
                memo
              end

              halt err(422, *errors) unless errors.empty?

              contact.set_pagerduty_credentials('service_key'  => params[:service_key],
                                                'subdomain'    => params[:subdomain],
                                                'username'     => params[:username],
                                                'password'     => params[:password])

              contact.pagerduty_credentials.to_json
            else
              if params[:address].nil?
                errors << "no address for '#{params[:id]}' media"
              end

              halt err(422, *errors) unless errors.empty?

              contact.set_address_for_media(params[:id], params[:address])
              contact.set_interval_for_media(params[:id], params[:interval])
              contact.set_rollup_threshold_for_media(params[:id], params[:rollup_threshold])

              {'address'          => contact.media[params[:id]],
               'interval'         => contact.media_intervals[params[:id]],
               'rollup_threshold' => contact.media_rollup_thresholds[params[:id]]}.to_json
            end
          end

          # delete a media of a contact
          app.delete('/contacts/:contact_id/media/:id') do
            contact = find_contact(params[:contact_id])
            contact.remove_media(params[:id])
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
            contact.timezone.name.to_json
          end

          # Removes the timezone of a contact
          # https://github.com/flpjck/flapjack/wiki/API#wiki-put_contacts_id_timezone
          app.delete('/contacts/:contact_id/timezone') do
            contact = find_contact(params[:contact_id])
            contact.timezone = nil
            status 204
          end

          app.post '/contacts/:contact_id/tags' do
            content_type :json

            tags = find_tags(params[:tag])
            contact = find_contact(params[:contact_id])
            contact.add_tags(*tags)
            contact.tags.to_json
          end

          app.post '/contacts/:contact_id/entity_tags' do
            content_type :json
            contact = find_contact(params[:contact_id])
            contact.entities.map {|e| e[:entity]}.each do |entity|
              next unless tags = params[:entity][entity.name]
              entity.add_tags(*tags)
            end
            contact_ent_tag = hashify(*contact.entities(:tags => true)) {|et|
              [et[:entity].name, et[:tags]]
            }
            contact_ent_tag.to_json
          end

          app.delete '/contacts/:contact_id/tags' do
            tags = find_tags(params[:tag])
            contact = find_contact(params[:contact_id])
            contact.delete_tags(*tags)
            status 204
          end

          app.delete '/contacts/:contact_id/entity_tags' do
            contact = find_contact(params[:contact_id])
            contact.entities.map {|e| e[:entity]}.each do |entity|
              next unless tags = params[:entity][entity.name]
              entity.delete_tags(*tags)
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
            contact_ent_tag = hashify(*contact.entities(:tags => true)) {|et|
              [et[:entity].name, et[:tags]]
            }
            contact_ent_tag.to_json
          end

        end

      end

    end

  end

end
