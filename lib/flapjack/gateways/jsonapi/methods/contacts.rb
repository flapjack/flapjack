#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/contact'
require 'flapjack/data/rule'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module Contacts

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Resources

            app.post '/contacts' do
              status 201
              resource_post(Flapjack::Data::Contact, 'contacts',
                :attributes => ['id', 'name', 'timezone'])
            end

            app.get %r{^/contacts(?:/)?([^/]+)?$} do
              requested_contacts = if params[:captures] && params[:captures][0]
                params[:captures][0].split(',').uniq
              else
                nil
              end

              status 200
              resource_get(Flapjack::Data::Contact, 'contacts',
                           requested_contacts, :sort => :name)
            end

            app.put %r{^/contacts/(.+)$} do
              contact_ids = params[:captures][0].split(',').uniq

              resource_put(Flapjack::Data::Contact, 'contacts', contact_ids,
                :attributes       => ['name', 'timezone'],
                :collection_links => {'media' => Flapjack::Data::Medium,
                                      'rules' => Flapjack::Data::Rule}
              )
              status 204
            end

            app.delete %r{^/contacts/(.+)$} do
              contact_ids = params[:captures][0].split(',').uniq

              resource_delete(Flapjack::Data::Contact, contact_ids)
              status 204
            end
          end
        end
      end
    end
  end
end
