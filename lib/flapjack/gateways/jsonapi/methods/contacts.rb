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

            app.class_eval do
              swagger_args = ['contacts', Flapjack::Data::Contact]

              swagger_wrappers(*swagger_args)
              swagger_post(*swagger_args)
              swagger_get(*swagger_args)
              swagger_patch(*swagger_args)
              swagger_delete(*swagger_args)
            end

            app.post '/contacts' do
              status 201
              resource_post(Flapjack::Data::Contact, 'contacts')
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

            app.patch %r{^/contacts/(.+)$} do
              contact_ids = params[:captures][0].split(',').uniq

              resource_patch(Flapjack::Data::Contact, 'contacts', contact_ids)
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
