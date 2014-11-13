#!/usr/bin/env ruby

require 'sinatra/base'

# NB: documentation changes required, this now uses individual check ids rather
# than v1's 'entity_name:check_name' pseudo-id

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module Tags

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Resources

            app.post '/tags' do
              status 201
              resource_post(Flapjack::Data::Tag, 'tags',
                :attributes       => ['id', 'name'],
                :collection_links => {'contacts' => Flapjack::Data::Contact,
                                      'rules' => Flapjack::Data::Rule}
              )
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

            # TODO should we not allow tags to be renamed?
            app.put %r{^/tags/(.+)$} do
              tag_ids = params[:captures][0].split(',').uniq

              resource_put(Flapjack::Data::Tag, 'tags', tag_ids,
                :attributes       => ['name'],
                :collection_links => {'contacts' => Flapjack::Data::Contact,
                                      'rules' => Flapjack::Data::Rule}
              )

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
