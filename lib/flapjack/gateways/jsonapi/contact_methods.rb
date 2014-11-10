#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/contact'
require 'flapjack/data/rule'

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      module ContactMethods

        SEMAPHORE_CONTACT_MASS_UPDATE = 'contact_mass_update'

        # module Helpers
        # end

        def self.registered(app)
          app.helpers Flapjack::Gateways::JSONAPI::Helpers
          # app.helpers Flapjack::Gateways::JSONAPI::ContactMethods::Helpers

          app.post '/contacts' do
            contacts_data, unwrap = wrapped_params('contacts')

            data_ids = contacts_data.reject {|c| c['id'].nil? }.
              map {|co| co['id'].to_s }

            contact_err = nil
            contact_ids = nil
            contacts    = nil

            Flapjack::Data::Contact.lock do

              # TODO should these overwrite instead?
              conflicted_ids = data_ids.select {|id|
                Flapjack::Data::Contact.exists?(id)
              }

              if conflicted_ids.length > 0
                contact_err = "Contacts already exist with the following ids: " +
                                conflicted_ids.join(', ')
              else
                contacts = contacts_data.collect do |contact_data|
                  Flapjack::Data::Contact.new(:id => contact_data['id'],
                    :name => contact_data['name'],
                    :timezone => contact_data['timezone'])
                end

                if invalid = contacts.detect {|c| c.invalid? }
                  contact_err = "Contact validation failed, " + invalid.errors.full_messages.join(', ')
                else
                  contact_ids = contacts.collect {|c| c.save; c.id }
                end
              end

            end

            halt err(403, contact_err) unless contact_err.nil?

            status 201
            response.headers['Location'] = "#{base_url}/contacts/#{contact_ids.join(',')}"
            contacts_as_json = Flapjack::Data::Contact.as_jsonapi(unwrap, *contacts)
            Flapjack.dump_json(:contacts => contacts_as_json)
          end

          # Returns all (/contacts) or some (/contacts/1,2,3) or one (/contacts/2) contact(s)
          # http://flapjack.io/docs/1.0/jsonapi/#contacts
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

            contacts_as_json = Flapjack::Data::Contact.as_jsonapi(unwrap, *contacts)
            Flapjack.dump_json({:contacts => contacts_as_json}.merge(meta))
          end

          app.patch '/contacts/:id' do
            Flapjack::Data::Contact.find_by_ids!(*params[:id].split(',')).each do |contact|
              apply_json_patch('contacts') do |op, property, linked, value|
                case op
                when 'replace'
                  if ['name', 'email', 'timezone'].include?(property)
                    contact.send("#{property}=".to_sym, value)
                  end
                when 'add'
                  case linked
                  when 'media'
                    Flapjack::Data::Medium.lock do
                      medium = Flapjack::Data::Medium.find_by_id(value)
                      unless medium.nil?
                        if existing_medium = contact.media.intersect(:type => medium.type).all.first
                          # TODO is this the right thing to do here? -- or just dissociate?
                          existing_medium.destroy
                        end
                        contact.media << medium
                      end
                    end
                  when 'rules'
                    rule = Flapjack::Data::Rule.find_by_id(value)
                    contact.rules << rule unless rule.nil?
                  end
                when 'remove'
                  case linked
                  when 'media'
                    medium = Flapjack::Data::Medium.find_by_id(value)
                    contact.media.delete(medium) unless medium.nil?
                  when 'rules'
                    rule = Flapjack::Data::Rule.find_by_id(value)
                    contact.rules.delete(rule) unless rule.nil?
                  end
                end
              end
              contact.save # no-op if the properties haven't changed
            end

            status 204
          end

          app.delete '/contacts/:id' do
            contact_ids = params[:id].split(',')
            contacts = Flapjack::Data::Contact.intersect(:id => contact_ids)
            missing_ids = contact_ids - contacts.ids

            unless missing_ids.empty?
              raise Sandstorm::Records::Errors::RecordsNotFound.new(Flapjack::Data::Contact, missing_ids)
            end

            contacts.destroy_all
            status 204
          end

        end

      end

    end

  end

end
