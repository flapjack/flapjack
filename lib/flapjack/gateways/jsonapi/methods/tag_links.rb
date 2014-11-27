#!/usr/bin/env ruby

require 'sinatra/base'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module TagLinks

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::ResourceLinks

            app.post %r{^/tags/(\S+)/links/(checks|rules)$} do
              tag_id     = params[:captures][0]
              assoc_type = params[:captures][1]

              resource_post_links(Flapjack::Data::Tag, tag_id, assoc_type,
                :collection_links => {'checks' => Flapjack::Data::Check,
                                      'rules'  => Flapjack::Data::Rule}
              )
              status 204
            end

            app.get %r{^/tags/(\S+)/links/(checks|rules)} do
              tag_id     = params[:captures][0]
              assoc_type = params[:captures][1]

              status 200
              resource_get_links(Flapjack::Data::Tag, tag_id, assoc_type,
                :collection_links => {'checks' => Flapjack::Data::Check,
                                      'rules'  => Flapjack::Data::Rule}
              )
            end

            app.put %r{^/tags/(\S+)/links/(checks|rules)$} do
              tag_id     = params[:captures][0]
              assoc_type = params[:captures][1]

              resource_put_links(Flapjack::Data::Tag, tag_id, assoc_type,
                :collection_links => {'checks' => Flapjack::Data::Check,
                                      'rules'  => Flapjack::Data::Rule}
              )
              status 204
            end

            app.delete %r{^/tags/(\S+)/links/(checks|rules)/(.+)$} do
              tag_id     = params[:captures][0]
              assoc_type = params[:captures][1]
              assoc_ids  = params[:captures][2].split(',').uniq

              assoc_klass = {'checks' => Flapjack::Data::Check,
                             'rules'  => Flapjack::Data::Rule}[assoc_type]

              resource_delete_links(Flapjack::Data::Tag, tag_id, assoc_type,
                assoc_klass, assoc_ids)
              status 204
            end
          end
        end
      end
    end
  end
end
