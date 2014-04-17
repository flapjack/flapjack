#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/contact'

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      module PagerdutyCredentialMethods

        module Helpers

          def split_pagerduty_credentials_ids(pagerduty_credentials_ids)
            pagerduty_credentials_ids.split(',').collect do |m_id|
              m_id =~ /\A(.+)_pagerduty\z/

              contact_id = $1
              halt err(422, "Could not get contact_id from pagerduty_credentials_id") if contact_id.nil?

              {:contact => find_contact(contact_id), :type => 'pagerduty'}
            end
          end

        end

        def self.registered(app)
          app.helpers Flapjack::Gateways::JSONAPI::Helpers
          app.helpers Flapjack::Gateways::JSONAPI::PagerdutyCredentialMethods::Helpers

          # Creates/overwrites pagerduty credentials for a contact
          app.post '/contacts/:contact_id/pagerduty_credentials' do

            pagerduty_credentials_data = params[:pagerduty_credentials]

            if pagerduty_credentials_data.nil? || !pagerduty_credentials_data.is_a?(Enumerable)
              halt err(422, "No valid pagerduty credentials were submitted")
            end

            fields = ['service_key', 'subdomain', 'username', 'password']

            pagerduty_credential = pagerduty_credentials_data.last

            if pagerduty_credential.nil? || !pagerduty_credential.is_a?(Hash)
              halt err(422, "No valid pagerduty credentials were submitted")
            end

            if (fields | pagerduty_credential.keys).size != field.size
              halt err(422, "Pagerduty credential data has incorrect fields")
            end

            semaphore = obtain_semaphore(SEMAPHORE_CONTACT_MASS_UPDATE)
            contact = Flapjack::Data::Contact.find_by_id(params[:contact_id], :redis => redis)
            if contact.nil?
              semaphore.release
              halt err(422, "Contact id:'#{contact_id}' could not be loaded")
            end

            pagerduty_credential_data = field.inject({}).each do |memo, field|
              memo[field] = pagerduty_credential[field]
            end

            contact.set_pagerduty_credentials(pagerduty_credential_data)
            semaphore.release

            pagerduty_credential_data['links'] = {'contacts' => [contact_id]}

            '{"pagerduty_credentials":[' + pagerduty_credential_data.to_json + ']}'
          end

          app.get %r{^/pagerduty_credentials(?:/)?([^/]+)?$} do
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

            if requested_contacts && requested_contacts.empty?
              raise Flapjack::Gateways::JSONAPI::ContactsNotFound.new(requested_contacts)
            end

            pagerduty_credentials_data = contacts.inject([]).each do |memo, contact|
              pdc = contact.pagerduty_credentials.dup
              pdc['links'] = {'contacts' => [contact.id]}
              memo << pdc
              memo
            end

            '{"pagerduty_credentials":' + pagerduty_credentials_data.to_json + '}'
          end

          # update one or more sets of pagerduty credentials
          app.patch '/pagerduty_credentials/:contact_id' do
            contact_ids = split_contact_ids(params[:contact_id])
            contacts = Flapjack::Data::Contact.find_by_ids(contacts, :logger => logger, :redis => redis)

            contacts.each do |contact|
              apply_json_patch('pagerduty_credentials') do |op, property, linked, value|
                if 'replace'.eql?(op)

                  pdc = contact.pagerduty_credentials.dup

                  case property
                  when 'service_key'
                    pdc['service_key'] = value
                    contact.set_pagerduty_credentials(pdc)
                  when 'subdomain'
                    pdc['subdomain'] = value
                    contact.set_pagerduty_credentials(pdc)
                  when 'username'
                    pdc['username'] = value
                    contact.set_pagerduty_credentials(pdc)
                  when 'password'
                    pdc['password'] = value
                    contact.set_pagerduty_credentials(pdc)
                  end
                end
              end
            end

            status 204
          end

          app.delete '/pagerduty_credentials/:contact_id' do
            contact_ids = split_contact_ids(params[:contact_id])
            contacts = Flapjack::Data::Contact.find_by_ids(contacts, :logger => logger, :redis => redis)

            contacts.each {|contact| contact.delete_pagerduty_credentials }
            status 204
          end

        end

      end

    end

  end

end
