#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/contact'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module Media

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Resources

            app.post '/media' do
              media_data, unwrap = wrapped_params('media')

              media = resource_post(Flapjack::Data::Medium, media_data,
                :attributes => ['id', 'type', 'address', 'interval',
                                'rollup_threshold'],
                :singular_links   => {'contact' => Flapjack::Data::Contact},
                :collection_links => {'routes' => Flapjack::Data::Route})

              status 201
              response.headers['Location'] = "#{base_url}/media/#{media.map(&:id).join(',')}"
              media_as_json = Flapjack::Data::Medium.as_jsonapi(unwrap, *media)
              Flapjack.dump_json(:media => media_as_json)
            end

            app.get %r{^/media(?:/)?([^/]+)?$} do
              requested_media = if params[:captures] && params[:captures][0]
                params[:captures][0].split(',').uniq
              else
                nil
              end

              unwrap = !requested_media.nil? && (requested_media.size == 1)

              media, meta = if requested_media
                requested = Flapjack::Data::Medium.find_by_ids!(*requested_media)

                if requested.empty?
                  raise Flapjack::Gateways::JSONAPI::RecordsNotFound.new(Flapjack::Data::Medium, requested_media)
                end

                [requested, {}]
              else
                paginate_get(Flapjack::Data::Medium.sort(:id, :order => 'alpha'),
                  :total => Flapjack::Data::Medium.count, :page => params[:page],
                  :per_page => params[:per_page])
              end

              media_as_json = Flapjack::Data::Medium.as_jsonapi(unwrap, *media)
              Flapjack.dump_json({:media => media_as_json}.merge(meta))
            end

            app.put %r{^/media/(.+)$} do
              medium_ids    = params[:captures][0].split(',').uniq
              media_data, _ = wrapped_params('media')

              resource_put(Flapjack::Data::Medium, medium_ids, media_data,
                :attributes => ['type', 'address', 'interval',
                                'rollup_threshold'],
                :singular_links   => {'contact' => Flapjack::Data::Contact},
                :collection_links => {'routes' => Flapjack::Data::Route}
              )

              status 204
            end

            app.delete %r{^/media/(.+)$} do
              media_ids = params[:captures][0].split(',').uniq
              resource_delete(Flapjack::Data::Medium, media_ids)
              status 204
            end
          end
        end
      end
    end
  end
end
