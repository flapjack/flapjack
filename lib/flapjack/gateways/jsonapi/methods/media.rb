#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/medium'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module Media

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Resources

            app.class_eval do
              swagger_args = ['media', Flapjack::Data::Medium]

              swagger_wrappers(*swagger_args)
              swagger_post(*swagger_args)
              swagger_get(*swagger_args)
              swagger_patch(*swagger_args)
              swagger_delete(*swagger_args)
            end

            app.post '/media' do
              status 201
              resource_post(Flapjack::Data::Medium, 'media')
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

            app.patch %r{^/media/(.+)$} do
              medium_ids    = params[:captures][0].split(',').uniq

              resource_patch(Flapjack::Data::Medium, 'media', medium_ids)
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
