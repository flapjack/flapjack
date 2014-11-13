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
              routes_data, unwrap = wrapped_params('routes')

              routes = resource_post(Flapjack::Data::Route, routes_data,
                :attributes       => ['id', 'state', 'time_restrictions'],
                :singular_links   => {'rule' => Flapjack::Data::Rule},
                :collection_links => {'media' => Flapjack::Data::Medium}
              )

              status 201
              response.headers['Location'] = "#{base_url}/routes/#{routes.map(&:id).join(',')}"
              routes_as_json = Flapjack::Data::Route.as_jsonapi(unwrap, *routes)
              Flapjack.dump_json(:routes => routes_as_json)
            end

            app.get %r{^/routes(?:/)?([^/]+)?$} do
              requested_routes = if params[:captures] && params[:captures][0]
                params[:captures][0].split(',').uniq
              else
                nil
              end

              unwrap = !requested_routes.nil? && (requested_routes.size == 1)

              routes, meta = if requested_routes
                requested = Flapjack::Data::Route.find_by_ids!(*requested_routes)

                if requested.empty?
                  raise Flapjack::Gateways::JSONAPI::RecordsNotFound.new(Flapjack::Data::Route, requested_routes)
                end

                [requested, {}]
              else
                paginate_get(Flapjack::Data::Route.sort(:id, :order => 'alpha'),
                  :total => Flapjack::Data::Route.count, :page => params[:page],
                  :per_page => params[:per_page])
              end

              status 200
              routes_as_json = Flapjack::Data::Route.as_jsonapi(unwrap, *routes)
              Flapjack.dump_json({:routes => routes_as_json}.merge(meta))
            end

            app.put %r{^/routes/(.+)$} do
              route_ids = params[:captures][0].split(',').uniq
              routes_data, _ = wrapped_params('rules')

              resource_put(Flapjack::Data::Route, route_ids, routes_data,
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
