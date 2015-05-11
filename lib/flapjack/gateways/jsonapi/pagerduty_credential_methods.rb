#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/contact'

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      module PagerdutyCredentialMethods

        SEMAPHORE_CONTACT_MASS_UPDATE = 'contact_mass_update'

        # module Helpers
        # end

        def self.registered(app)
          app.helpers Flapjack::Gateways::JSONAPI::Helpers
          # app.helpers Flapjack::Gateways::JSONAPI::PagerdutyCredentialMethods::Helpers

          # Creates/overwrites pagerduty credentials for a contact
          app.post '/contacts/:contact_id/pagerduty_credentials' do

            pagerduty_credentials_data = params[:pagerduty_credentials]

            if pagerduty_credentials_data.nil? || !pagerduty_credentials_data.is_a?(Enumerable)
              halt err(422, "No valid pagerduty credentials were submitted")
            end

            fields = ['service_key', 'subdomain', 'token', 'username', 'password']

            pagerduty_credential = pagerduty_credentials_data.last

            if pagerduty_credential.nil? || !pagerduty_credential.is_a?(Hash)
              halt err(422, "No valid pagerduty credentials were submitted")
            end

            if (fields | pagerduty_credential.keys).size != fields.size
              halt err(422, "Pagerduty credential data has incorrect fields")
            end

            semaphore = obtain_semaphore(SEMAPHORE_CONTACT_MASS_UPDATE)
            contact = Flapjack::Data::Contact.find_by_id(params[:contact_id], :redis => redis)
            if contact.nil?
              semaphore.release
              halt err(422, "Contact id: '#{params[:contact_id]}' could not be loaded")
            end

            pagerduty_credential_data = fields.inject({}) do |memo, field|
              memo[field] = pagerduty_credential[field]
              memo
            end

            contact.set_pagerduty_credentials(pagerduty_credential_data)
            semaphore.release

            pagerduty_credential_data['links'] = {'contacts' => [contact.id]}

            status 201
            response.headers['Location'] = "#{base_url}/pagerduty_credentials/#{contact.id}"
            Flapjack.dump_json([contact.id])
          end

          app.get %r{^/pagerduty_credentials(?:/)?([^/]+)?$} do
            contacts = if params[:captures] && params[:captures][0]
              params[:captures][0].split(',').uniq.collect {|c_id| find_contact(c_id)}
            else
              Flapjack::Data::Contact.all(:redis => redis)
            end

            pagerduty_credentials_data = contacts.inject([]) do |memo, contact|
              pdc = contact.pagerduty_credentials

              unless pdc.nil?
                pd_data = pdc.clone
                pd_data['links'] = {'contacts' => [contact.id]}
                memo << pd_data
              end

              memo
            end

            '{"pagerduty_credentials":' + Flapjack.dump_json(pagerduty_credentials_data) + '}'
          end

          # update one or more sets of pagerduty credentials
          app.patch '/pagerduty_credentials/:contact_id' do
            params[:contact_id].split(',').uniq.collect {|c_id| find_contact(c_id)}.each do |contact|
              apply_json_patch('pagerduty_credentials') do |op, property, linked, value|
                if 'replace'.eql?(op)

                  pdc = contact.pagerduty_credentials
                  pd_data = pdc.nil? ? {} : pdc.clone

                  case property
                  when 'service_key'
                    pd_data['service_key'] = value
                    contact.set_pagerduty_credentials(pd_data)
                  when 'subdomain'
                    pd_data['subdomain'] = value
                    contact.set_pagerduty_credentials(pd_data)
                  when 'token'
                    pd_data['token'] = value
                    contact.set_pagerduty_credentials(pd_data)
                  when 'username'
                    pd_data['username'] = value
                    contact.set_pagerduty_credentials(pd_data)
                  when 'password'
                    pd_data['password'] = value
                    contact.set_pagerduty_credentials(pd_data)
                  end
                end
              end
            end

            status 204
          end

          app.delete '/pagerduty_credentials/:contact_id' do
            params[:contact_id].split(',').uniq.collect {|c_id|
              find_contact(c_id)
            }.each {|contact|
              contact.delete_pagerduty_credentials
            }
            status 204
          end

        end

      end

    end

  end

end
