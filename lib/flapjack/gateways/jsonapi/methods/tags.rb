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
              tags_data, unwrap = wrapped_params('tags')

              tags = resource_post(Flapjack::Data::Tag, rules_data,
                :attributes       => ['id', 'name'],
                :collection_links => {'contacts' => Flapjack::Data::Contact,
                                      'rules' => Flapjack::Data::Rule}
              )

              status 201
              response.headers['Location'] = "#{base_url}/tags/#{tags.map(&:id).join(',')}"
              tags_as_json = Flapjack::Data::Tag.as_jsonapi(unwrap, *tags)
              Flapjack.dump_json(:tags => tags_as_json)
            end

            app.get %r{^/tags(?:/)?(.+)?$} do
              requested_tags = if params[:captures] && params[:captures][0]
                params[:captures][0].split(',').uniq
              else
                nil
              end

              unwrap = !requested_tags.nil? && (requested_tags.size == 1)

              tags, meta = if requested_tags
                requested = Flapjack::Data::Tag.intersect(:id => requested_tags).all

                if requested.empty?
                  raise Flapjack::Gateways::JSONAPI::RecordsNotFound.new(Flapjack::Data::Tag, requested_tags)
                end

                [requested, {}]
              else
                paginate_get(Flapjack::Data::Tag.sort(:name, :order => 'alpha'),
                  :total => Flapjack::Data::Tag.count, :page => params[:page],
                  :per_page => params[:per_page])
              end

              tags_as_json = Flapjack::Data::Tag.as_jsonapi(unwrap, *tags)
              Flapjack.dump_json({:tags => tags_as_json}.merge(meta))
            end

            # TODO should we not allow tags to be renamed?
            app.put %r{^/tags/(.+)$} do
              tag_ids = params[:captures][0].split(',').uniq
              tags_data, _ = wrapped_params('tags')

              resource_put(Flapjack::Data::Tag, tag_ids, tags_data,
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
