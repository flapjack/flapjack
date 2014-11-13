#!/usr/bin/env ruby

require 'sinatra/base'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module CheckLinks

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::ResourceLinks

            app.post %r{^/checks/(#{Flapjack::UUID_RE})/links/(tags)$} do
              check_id   = params[:captures][0]
              assoc_type = params[:captures][1]

              resource_post_links(Flapjack::Data::Check, check_id, assoc_type,
                :collection_links => {'tags' => Flapjack::Data::Tag})
              status 204
            end

            app.get %r{^/checks/(#{Flapjack::UUID_RE})/links/(tags)} do
              check_id   = params[:captures][0]
              assoc_type = params[:captures][1]

              status 200
              resource_get_links(Flapjack::Data::Check, check_id, assoc_type,
                :collection_links => {'tags' => Flapjack::Data::Tag})
            end

            app.put %r{^/checks/(#{Flapjack::UUID_RE})/links/(tags)$} do
              check_id   = params[:captures][0]
              assoc_type = params[:captures][1]

              resource_put_links(Flapjack::Data::Check, check_id, assoc_type,
                :collection_links => {'tags' => Flapjack::Data::Tag})
              status 204
            end

            app.delete %r{^/checks/(#{Flapjack::UUID_RE})/links/(tags)/(.+)$} do
              check_id   = params[:captures][0]
              assoc_type = params[:captures][1]
              assoc_ids  = params[:captures][2].split(',').uniq

              assoc_klass = {'tags' => Flapjack::Data::Tag}[assoc_type]

              resource_delete_links(Flapjack::Data::Check, check_id, assoc_type,
                assoc_klass, assoc_ids)
              status 204
            end
          end
        end
      end
    end
  end
end
