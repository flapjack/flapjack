#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/contact'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module Routes

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Resources

            app.post '/routes' do
              status 201
              resource_post(Flapjack::Data::Route, 'routes',
                :attributes       => ['id', 'state', 'time_restrictions'],
                :singular_links   => {'rule' => Flapjack::Data::Rule},
                :collection_links => {'media' => Flapjack::Data::Medium}
              )
            end

            app.get %r{^/routes(?:/)?([^/]+)?$} do
              requested_routes = if params[:captures] && params[:captures][0]
                params[:captures][0].split(',').uniq
              else
                nil
              end

              status 200
              resource_get(Flapjack::Data::Route, 'routes', requested_routes,
                           :sort => :id)
            end

            app.put %r{^/routes/(.+)$} do
              route_ids = params[:captures][0].split(',').uniq

              resource_put(Flapjack::Data::Route, 'routes', route_ids,
                :attributes       => ['state', 'time_restrictions'],
                :singular_links   => {'rule' => Flapjack::Data::Rule},
                :collection_links => {'media' => Flapjack::Data::Medium}
              )
              status 204
            end

            app.delete %r{^/routes/(.+)$} do
              route_ids = params[:captures][0].split(',').uniq

              resource_delete(Flapjack::Data::Route, route_ids)
              status 204
            end
          end
        end
      end
    end
  end
end
