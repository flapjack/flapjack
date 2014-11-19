#!/usr/bin/env ruby

require 'sinatra/base'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module RouteLinks

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::ResourceLinks

            app.post %r{^/routes/(#{Flapjack::UUID_RE})/links/(rule|media)$} do
              route_id   = params[:captures][0]
              assoc_type = params[:captures][1]

              resource_post_links(Flapjack::Data::Route, route_id, assoc_type,
                :singular_links   => {'rule' => Flapjack::Data::Rule},
                :collection_links => {'media' => Flapjack::Data::Medium}
              )
              status 204
            end

            app.get %r{^/routes/(#{Flapjack::UUID_RE})/links/(rule|media)} do
              route_id   = params[:captures][0]
              assoc_type = params[:captures][1]

              status 200
              resource_get_links(Flapjack::Data::Route, route_id, assoc_type,
                :singular_links   => {'rule' => Flapjack::Data::Rule},
                :collection_links => {'media' => Flapjack::Data::Medium}
              )
            end

            app.put %r{^/routes/(#{Flapjack::UUID_RE})/links/(rule|media)$} do
              route_id   = params[:captures][0]
              assoc_type = params[:captures][1]

              resource_put_links(Flapjack::Data::Route, route_id, assoc_type,
                :singular_links   => {'rule' => Flapjack::Data::Rule},
                :collection_links => {'media' => Flapjack::Data::Medium}
              )
              status 204
            end

            app.delete %r{^/routes/(#{Flapjack::UUID_RE})/links/(media)/(.+)$} do
              route_id   = params[:captures][0]
              assoc_type = params[:captures][1]
              assoc_ids  = params[:captures][2].split(',').uniq

              assoc_klass = {'media' => Flapjack::Data::Medium}[assoc_type]

              resource_delete_links(Flapjack::Data::Route, route_id, assoc_type,
                assoc_klass, assoc_ids)
              status 204
            end
          end
        end
      end
    end
  end
end
