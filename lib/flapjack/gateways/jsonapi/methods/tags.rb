#!/usr/bin/env ruby

require 'sinatra/base'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module Tags

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Resources

            app.class_eval do
              swagger_args = ['tags', Flapjack::Data::Tag]

              include Swagger::Blocks
              swagger_post(*swagger_args)
              swagger_get(*swagger_args)
              swagger_put(*swagger_args)
              swagger_delete(*swagger_args)
            end

            app.post '/tags' do
              status 201
              resource_post(Flapjack::Data::Tag, 'tags')
            end

            app.get %r{^/tags(?:/)?(.+)?$} do
              requested_tags = if params[:captures] && params[:captures][0]
                params[:captures][0].split(',').uniq
              else
                nil
              end

              status 200
              resource_get(Flapjack::Data::Tag, 'tags', requested_tags,
                           :sort => :name)
            end

            # NB: tags cannot be renamed, this is only present for updating of
            # associations, which can also be done through tag_links.rb methods
            app.patch %r{^/tags/(.+)$} do
              tag_ids = params[:captures][0].split(',').uniq

              resource_patch(Flapjack::Data::Tag, 'tags', tag_ids)
              status 204
            end

            app.delete %r{^/tags/(.+)$} do
              tag_ids = params[:captures][0].split(',').uniq

              resource_delete(Flapjack::Data::Tag, tag_ids)
              status 204
            end
          end
        end
      end
    end
  end
end
