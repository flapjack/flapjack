#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/contact'

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      module RouteMethods

        # module Helpers
        # end

        def self.registered(app)
          app.helpers Flapjack::Gateways::JSONAPI::Helpers
          # app.helpers Flapjack::Gateways::JSONAPI::RouteMethods::Helpers

          # TODO POST

          app.get %r{^/routes(?:/)?([^/]+)?$} do
            requested_routes = if params[:captures] && params[:captures][0]
              params[:captures][0].split(',').uniq
            else
              nil
            end

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

            routes_as_json = if routes.empty?
              []
            else
              route_ids = routes.map(&:id)
              linked_rule_ids = Flapjack::Data::Route.intersect(:id => route_ids).
                associated_ids_for(:rule)

              routes.collect {|route|
                route.as_json(:rule_id => linked_rule_ids[route.id])
              }
            end

            Flapjack.dump_json({:routes => routes_as_json}.merge(meta))
          end

          app.patch '/routes/:id' do
            Flapjack::Data::Route.find_by_ids!(*params[:id].split(',')).each do |route|

              apply_json_patch('routes') do |op, property, linked, value|
                case op
                when 'replace'
                  # TODO change to use Flapjack::Data::State object
                  if ['state'].include?(property)
                    route.send("#{property}=".to_sym, value)
                  end

                  # TODO time restrictions

                when 'add'
                  case linked
                  when 'media'
                    Flapjack::Data::Medium.lock do
                      medium = Flapjack::Data::Medium.find_by_id(value)
                      unless medium.nil?
                        if existing_medium = route.media.intersect(:type => medium.type).all.first
                          # just dissociate, not delete record
                          route.media.delete(existing_medium)
                        end
                        route.media << medium
                      end
                    end
                  end
                when 'remove'
                  case linked
                  when 'media'
                    medium = Flapjack::Data::Medium.find_by_id(value)
                    route.media.delete(medium) unless medium.nil?
                  end
                end
              end
              route.save # no-op if the record hasn't changed
            end

            status 204
          end

          # TODO DELETE

        end

      end

    end

  end

end
