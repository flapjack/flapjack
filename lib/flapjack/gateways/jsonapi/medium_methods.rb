#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/contact'

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      module MediumMethods

        module Helpers
        end

        def self.registered(app)
          app.helpers Flapjack::Gateways::JSONAPI::Helpers
          # app.helpers Flapjack::Gateways::JSONAPI::MediumMethods::Helpers

          # Creates media records for a contact
          app.post '/contacts/:contact_id/media' do
            media_data = wrapped_params('media')

            media_err = nil
            media_ids = nil
            media = nil

            Flapjack::Data::Contact.lock(Flapjack::Data::Medium) do

              contact = Flapjack::Data::Contact.find_by_id(params[:contact_id])

              if contact.nil?
                media_err = "Contact with id '#{params[:contact_id]}' could not be loaded"
              else
                media = media_data.collect do |medium_data|
                  Flapjack::Data::Medium.new(:id => medium_data['id'],
                    :type => medium_data['type'],
                    :address => medium_data['address'],
                    :interval => medium_data['interval'],
                    :rollup_threshold => medium_data['rollup_threshold'])
                end

                if invalid = media.detect {|m| m.invalid? }
                  media_err = "Medium validation failed, " + invalid.errors.full_messages.join(', ')
                else
                  media_ids = media.collect {|m|
                    m.save
                    contact_media = contact.media
                    if existing_medium = contact_media.intersect(:type => m.type).all.first
                      # TODO is this the right thing to do here?
                      existing_medium.destroy
                    end
                    contact_media << m
                    m.id
                  }
                end

              end
            end

            if media_err
              halt err(403, media_err)
            end

            status 201
            response.headers['Location'] = "#{base_url}/media/#{media_ids.join(',')}"
            Flapjack.dump_json(media_ids)
          end

          app.get %r{^/media(?:/)?([^/]+)?$} do
            requested_media = if params[:captures] && params[:captures][0]
              params[:captures][0].split(',').uniq
            else
              nil
            end

            media = if requested_media
              Flapjack::Data::Medium.find_by_ids!(*requested_media)
            else
              Flapjack::Data::Medium.all
            end

            media_ids = media.map(&:id)
            linked_contact_ids = Flapjack::Data::Medium.associated_ids_for_contact(*media_ids)
            linked_notification_rule_state_ids = Flapjack::Data::Medium.associated_ids_for_notification_rule_states(*media_ids)

            media_as_json = media.collect {|medium|
              medium.as_json(:contact_ids => [linked_contact_ids[medium.id]],
                             :notification_rule_state_ids => linked_notification_rule_state_ids[medium.id])
            }

            Flapjack.dump_json(:media => media_as_json)
          end

          app.patch '/media/:id' do
            Flapjack::Data::Medium.find_by_ids!(*params[:id].split(',')).each do |medium|
              apply_json_patch('media') do |op, property, linked, value|
                case op

                when 'replace'
                  if ['type', 'address', 'interval', 'rollup_threshold'].include?(property)
                    medium.send("#{property}=".to_sym, value)
                  end

                when 'add'
                  case linked
                  when 'notification_rule_state'

                    Flapjack::Data::Medium.lock do
                      notification_rule_state = Flapjack::Data::NotificationRuleState.find_by_id(value)
                      unless notification_rule_state.nil?
                        if existing_medium = notification_rule_state.media.intersect(:type => medium.type).all.first
                          # just dissociate, not delete record
                          notification_rule_state.media.delete(existing_medium)
                        end
                        notification_rule_state.media << medium
                      end
                    end
                  end
                when 'remove'
                  case linked
                  when 'notification_rule_state'
                    notification_rule_state = Flapjack::Data::NotificationRuleState.find_by_id(value)
                    notification_rule_state.media.delete(medium) unless notification_rule_state.nil?
                  end
                end
              end
              medium.save # no-op if the record hasn't changed
            end

            status 204
          end

          app.delete '/media/:id' do
            Flapjack::Data::Medium.find_by_ids!(*params[:id].split(',')).map(&:destroy)

            status 204
          end

        end

      end

    end

  end

end
