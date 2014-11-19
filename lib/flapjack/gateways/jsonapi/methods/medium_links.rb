#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/contact'
require 'flapjack/data/rule'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module MediumLinks

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::ResourceLinks

            app.post %r{^/media/(#{Flapjack::UUID_RE})/links/(contact|routes)$} do
              medium_id  = params[:captures][0]
              assoc_type = params[:captures][1]

              resource_post_links(Flapjack::Data::Medium, medium_id, assoc_type,
                :singular_links   => {'contact' => Flapjack::Data::Contact},
                :collection_links => {'routes' => Flapjack::Data::Route})
              status 204
            end

            app.get %r{^/media/(#{Flapjack::UUID_RE})/links/(contact|routes)} do
              medium_id = params[:captures][0]
              assoc_type = params[:captures][1]

              status 200
              resource_get_links(Flapjack::Data::Medium, medium_id, assoc_type,
                :singular_links   => {'contact' => Flapjack::Data::Contact},
                :collection_links => {'routes' => Flapjack::Data::Route})
            end

            app.put %r{^/media/(#{Flapjack::UUID_RE})/links/(contact|routes)$} do
              medium_id = params[:captures][0]
              assoc_type = params[:captures][1]

              resource_put_links(Flapjack::Data::Medium, medium_id, assoc_type,
                :singular_links   => {'contact' => Flapjack::Data::Contact},
                :collection_links => {'routes' => Flapjack::Data::Route})
              status 204
            end

            app.delete %r{^/media/(#{Flapjack::UUID_RE})/links/(contact)$} do
              medium_id = params[:captures][0]
              assoc_type = params[:captures][1]

              assoc_klass = {'contact' => Flapjack::Data::Contact}[assoc_type]

              resource_delete_link(Flapjack::Data::Medium, medium_id, assoc_type,
                assoc_klass)
              status 204
            end

            app.delete %r{^/media/(#{Flapjack::UUID_RE})/links/(routes)/(.+)$} do
              medium_id = params[:captures][0]
              assoc_type = params[:captures][1]
              assoc_ids  = params[:captures][2].split(',').uniq

              assoc_klass = {'routes' => Flapjack::Data::Route}[assoc_type]

              resource_delete_links(Flapjack::Data::Medium, medium_id, assoc_type,
                assoc_klass, assoc_ids)
              status 204
            end

          end
        end
      end
    end
  end
end
