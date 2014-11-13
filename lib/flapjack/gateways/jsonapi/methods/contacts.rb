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
              contacts_data, unwrap = wrapped_params('contacts')

              contacts = resource_post(Flapjack::Data::Contact, contacts_data,
                :attributes => ['id', 'name', 'timezone'])

              status 201
              response.headers['Location'] = "#{base_url}/contacts/#{contacts.map(&:id).join(',')}"
              contacts_as_json = Flapjack::Data::Contact.as_jsonapi(unwrap, *contacts)
              Flapjack.dump_json(:contacts => contacts_as_json)
            end

            app.get %r{^/contacts(?:/)?([^/]+)?$} do
              requested_contacts = if params[:captures] && params[:captures][0]
                params[:captures][0].split(',').uniq
              else
                nil
              end

              unwrap = !requested_contacts.nil? && (requested_contacts.size == 1)

              contacts, meta = if requested_contacts
                requested = Flapjack::Data::Contact.find_by_ids!(*requested_contacts)

                if requested.empty?
                  raise Flapjack::Gateways::JSONAPI::RecordsNotFound.new(Flapjack::Data::Contact, requested_contacts)
                end

                [requested, {}]
              else
                paginate_get(Flapjack::Data::Contact.sort(:name, :order => 'alpha'),
                  :total => Flapjack::Data::Contact.count, :page => params[:page],
                  :per_page => params[:per_page])
              end

              status 200
              contacts_as_json = Flapjack::Data::Contact.as_jsonapi(unwrap, *contacts)
              Flapjack.dump_json({:contacts => contacts_as_json}.merge(meta))
            end

            app.put %r{^/contacts/(.+)$} do
              contact_ids = params[:captures][0].split(',').uniq
              contacts_data, _ = wrapped_params('contacts')

              resource_put(Flapjack::Data::Contact, contact_ids, contacts_data,
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
