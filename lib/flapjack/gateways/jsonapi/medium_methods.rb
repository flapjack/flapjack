#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/contact'

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      module MediumMethods

        SEMAPHORE_CONTACT_MASS_UPDATE = 'contact_mass_update'

        module Helpers

          def obtain_semaphore(resource)
            semaphore = nil
            strikes = 0
            begin
              semaphore = Flapjack::Data::Semaphore.new(resource, :redis => redis, :expiry => 30)
            rescue Flapjack::Data::Semaphore::ResourceLocked
              strikes += 1
              raise Flapjack::Gateways::JSONAPI::ResourceLocked.new(resource) unless strikes < 3
              sleep 1
              retry
            end
            raise Flapjack::Gateways::JSONAPI::ResourceLocked.new(resource) unless semaphore
            semaphore
          end

          # TODO validate that media type exists in redis
          def split_media_ids(media_ids)

            contact_cache = {}

            known_media_identifiers = Flapjack::Data::Contact::ALL_MEDIA.reject{|m| m == 'pagerduty'}.join('|')
            media_ids.split(',').uniq.collect do |m_id|
              m_id =~ /\A(.+)_(#{known_media_identifiers})\z/

              contact_id = $1
              media_type = $2
              halt err(422, "Could not get contact_id from media_id '#{m_id}'") if contact_id.nil?
              halt err(422, "Could not get media type from media_id '#{m_id}'") if media_type.nil?

              contact_cache[contact_id] ||= find_contact(contact_id)

              {:contact => contact_cache[contact_id], :type => media_type}
            end
          end

        end

        def self.registered(app)
          app.helpers Flapjack::Gateways::JSONAPI::Helpers
          app.helpers Flapjack::Gateways::JSONAPI::MediumMethods::Helpers

          # Creates media records for a contact
          app.post '/contacts/:contact_id/media' do
            media_data = params[:media]

            if media_data.nil? || !media_data.is_a?(Enumerable)
              halt err(422, "No valid media were submitted")
            end

            media_id_re = /^#{params[:contact_id]}_(?:#{Flapjack::Data::Contact::ALL_MEDIA.join('|')}$)/

            unless media_data.all? {|m| m['id'].nil? || media_id_re === m['id'] }
              halt err(422, "Media creation cannot include non-conformant IDs")
            end

            semaphore = obtain_semaphore(SEMAPHORE_CONTACT_MASS_UPDATE)
            contact = Flapjack::Data::Contact.find_by_id(params[:contact_id], :redis => redis)
            if contact.nil?
              semaphore.release
              halt err(422, "Contact id: '#{params[:contact_id]}' could not be loaded")
            end

            media_data.each do |medium_data|
              type = medium_data['type']
              contact.set_address_for_media(type, medium_data['address'])
              contact.set_interval_for_media(type, medium_data['interval'])
              contact.set_rollup_threshold_for_media(type, medium_data['rollup_threshold'])
              medium_data['id'] = "#{contact.id}_#{type}"
            end

            semaphore.release

            media_ids = media_data.collect {|md| md['id']}

            status 201
            response.headers['Location'] = "#{base_url}/media/#{media_ids.join(',')}"
            Flapjack.dump_json(media_ids)
          end

          # get one or more media records; media ids are, for Flapjack
          # v1, composed of "#{contact.id}_#{media_type}"
          app.get %r{^/media(?:/)?([^/]+)?$} do
            media_list_cache = {}
            contact_media = if params[:captures] && params[:captures][0]
              split_media_ids(params[:captures][0])
            else
              Flapjack::Data::Contact.all(:redis => redis).collect do |contact|
                media_list_cache[contact.id] ||= contact.media_list
                media_list_cache[contact.id].collect do |media_type|
                  {:contact => contact, :type => media_type}
                end
              end.flatten(1)
            end

            media_data = contact_media.inject([]) do |memo, contact_media_type|
              contact = contact_media_type[:contact]
              media_type = contact_media_type[:type]

              media_list_cache[contact.id] ||= contact.media_list
              if media_list_cache[contact.id].include?(media_type)
                medium_id = "#{contact.id}_#{media_type}"
                int = contact.media_intervals[media_type]
                rut = contact.media_rollup_thresholds[media_type]
                memo <<
                  {:id               => medium_id,
                   :type             => media_type,
                   :address          => contact.media[media_type],
                   :interval         => int.nil? ? nil : int.to_i,
                   :rollup_threshold => rut.nil? ? nil : rut.to_i,
                   :links            => {:contacts => [contact.id]}}
              end

              memo
            end

            '{"media":' + Flapjack.dump_json(media_data) + '}'
          end

          # update one or more media records; media ids are, for Flapjack
          # v1, composed of "#{contact.id}_#{media_type}"
          app.patch '/media/:id' do
            media_list_cache = {}
            split_media_ids(params[:id]).each do |contact_media_type|
              contact = contact_media_type[:contact]
              media_type = contact_media_type[:type]
              media_list_cache[contact.id] ||= contact.media_list
              next unless media_list_cache[contact.id].include?(media_type)
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
          app.delete '/media/:id' do
            media_list_cache = {}
            split_media_ids(params[:id]).each do |contact_media_type|
              contact = contact_media_type[:contact]
              media_type = contact_media_type[:type]
              media_list_cache[contact.id] ||= contact.media_list
              next unless media_list_cache[contact.id].include?(media_type)
              contact.remove_media(media_type)
            end
            status 204
          end

        end

      end

    end

  end

end
