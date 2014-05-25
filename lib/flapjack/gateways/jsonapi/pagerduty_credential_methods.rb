#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/contact'
require 'flapjack/data/pagerduty_credentials'

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      module PagerdutyCredentialMethods

        # module Helpers
        # end

        def self.registered(app)
          app.helpers Flapjack::Gateways::JSONAPI::Helpers
          # app.helpers Flapjack::Gateways::JSONAPI::PagerdutyCredentialMethods::Helpers

          app.post '/contacts/:contact_id/pagerduty_credentials' do
            pagerduty_credentials_data = wrapped_params('pagerduty_credentials')

            pagerduty_credentials_err = nil
            pagerduty_credentials_id = nil
            pagerduty_credentials = nil

            Flapjack::Data::Contact.send(:lock, Flapjack::Data::PagerdutyCredentials) do
              contact = Flapjack::Data::Contact.find_by_id(params[:contact_id])

              if contact.nil?
                pagerduty_credentials_err = "Contact with id '#{params[:contact_id]}' could not be loaded"
              else
                pagerduty_credentials =
                  Flapjack::Data::PagerdutyCredentials.new(:id => pagerduty_credentials_data.last['id'],
                    :service_key => pagerduty_credentials_data.last['service_key'],
                    :subdomain => pagerduty_credentials_data.last['subdomain'],
                    :username => pagerduty_credentials_data.last['username'],
                    :password => pagerduty_credentials_data.last['password'])

                if pagerduty_credentials.invalid?
                  pagerduty_credentials_err = "PagerDuty credentials validation failed, " +
                    pagerduty_credentials.errors.full_messages.join(', ')
                else
                  pagerduty_credentials.save
                  if existing_pagerduty_credentials = contact.pagerduty_credentials
                    p existing_pagerduty_credentials
                    # TODO is this the right thing to do here?
                    existing_pagerduty_credentials.destroy
                  end
                  contact.pagerduty_credentials = pagerduty_credentials
                end
              end
            end

            if pagerduty_credentials_err
              halt err(403, pagerduty_credentials_err)
            end

            status 201
            response.headers['Location'] = "#{base_url}/pagerduty_credentials/#{pagerduty_credentials.id}"
            [pagerduty_credentials.id].to_json
          end

          app.get %r{^/pagerduty_credentials(?:/)?([^/]+)?$} do
            requested_pagerduty_credentials = if params[:captures] && params[:captures][0]
              params[:captures][0].split(',').uniq
            else
              nil
            end

            pagerduty_credentials = if requested_pagerduty_credentials
              Flapjack::Data::PagerdutyCredentials.find_by_ids!(requested_pagerduty_credentials)
            else
              Flapjack::Data::PagerdutyCredentials.all
            end

            pagerduty_credentials_ids = pagerduty_credentials.map(&:id)
            linked_contact_ids = Flapjack::Data::PagerdutyCredentials.associated_ids_for_contact(pagerduty_credentials_ids)

            pagerduty_credentials_json = pagerduty_credentials.collect {|pdc|
              pdc.as_json(:contact_id => linked_contact_ids[pdc.id]).to_json
            }.join(",")

            '{"pagerduty_credentials":[' + pagerduty_credentials_json + ']}'
          end

          app.patch '/pagerduty_credentials/:id' do
            Flapjack::Data::PagerdutyCredentials.find_by_ids!(params[:id].split(',')).
              each do |pagerduty_credentials|

              apply_json_patch('pagerduty_credentials') do |op, property, linked, value|
                if 'replace'.eql?(op)
                  if ['service_key', 'subdomain', 'username', 'password'].include?(property)
                    pagerduty_credentials.send("#{property}=".to_sym, value)
                  end
                end
              end
              pagerduty_credentials.save # no-op if the record hasn't changed
            end

            status 204
          end

          app.delete '/pagerduty_credentials/:id' do
            Flapjack::Data::PagerdutyCredentials.find_by_ids!(params[:id].split(',')).
              map(&:destroy)

            status 204
          end

        end

      end

    end

  end

end
