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
              status 201
              resource_post(Flapjack::Data::Medium, 'media',
                :attributes => ['id', 'type', 'address', 'interval',
                                'rollup_threshold'],
                :singular_links   => {'contact' => Flapjack::Data::Contact},
                :collection_links => {'routes' => Flapjack::Data::Route})
            end

            app.get %r{^/media(?:/)?([^/]+)?$} do
              requested_media = if params[:captures] && params[:captures][0]
                params[:captures][0].split(',').uniq
              else
                nil
              end

              status 200
              resource_get(Flapjack::Data::Medium, 'media', requested_media,
                           :sort => :id)
            end

            app.put %r{^/media/(.+)$} do
              medium_ids    = params[:captures][0].split(',').uniq

              resource_put(Flapjack::Data::Medium, 'media', medium_ids,
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
