#!/usr/bin/env ruby

require 'sinatra/base'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module ResourceLinks

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::ResourceLinks

            Flapjack::Gateways::JSONAPI::RESOURCE_CLASSES.each do |resource_class|
              endpoint = resource_class.jsonapi_type.pluralize.downcase

              singular_links, multiple_links = resource_class.association_klasses

              assocs       = singular_links.empty? ? nil : singular_links.keys.map(&:to_s).join('|')
              multi_assocs = multiple_links.empty? ? nil : multiple_links.keys.map(&:to_s).join('|')

              if assocs.nil?
                assocs = multi_assocs
              elsif !multi_assocs.nil?
                assocs += "|#{multi_assocs}"
              end

              app.class_eval do
                unless assocs.nil?
                  swagger_get_links(endpoint, resource_class)
                  swagger_patch_links(endpoint, resource_class)
                end

                unless multi_assocs.nil?
                  swagger_post_links(endpoint, resource_class)
                  swagger_delete_links(endpoint, resource_class)
                end
              end

              id_patt = if Flapjack::Data::Tag.eql?(resource_class)
                "\\S+"
              else
                Flapjack::UUID_RE
              end

              unless assocs.nil?
                app.get %r{^/#{endpoint}/(#{id_patt})/(?:links/)?(#{assocs})} do
                  resource_id = params[:captures][0]
                  assoc_type  = params[:captures][1]

                  status 200
                  resource_get_links(resource_class, endpoint, resource_id, assoc_type)
                end

                app.patch %r{^/#{endpoint}/(#{id_patt})/links/(#{assocs})$} do
                  resource_id = params[:captures][0]
                  assoc_type  = params[:captures][1]

                  status 204
                  resource_patch_links(resource_class, endpoint, resource_id, assoc_type)
                end
              end

              unless multi_assocs.nil?
                app.post %r{^/#{endpoint}/(#{id_patt})/links/(#{multi_assocs})$} do
                  resource_id = params[:captures][0]
                  assoc_type  = params[:captures][1]

                  status 204
                  resource_post_links(resource_class, endpoint, resource_id, assoc_type)
                end

                app.delete %r{^/#{endpoint}/(#{id_patt})/links/(#{multi_assocs})$} do
                  resource_id = params[:captures][0]
                  assoc_type  = params[:captures][1]

                  status 204
                  resource_delete_links(resource_class, endpoint, resource_id, assoc_type)
                end
              end
            end
          end
        end
      end
    end
  end
end
