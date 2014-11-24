#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/contact'
require 'flapjack/data/rule'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module Rules

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Resources

            app.post '/rules' do
              status 201
              resource_post(Flapjack::Data::Rule, 'rules',
                :attributes       => ['id'],
                :singular_links   => {'contact' => Flapjack::Data::Contact},
                :collection_links => {'tags' => Flapjack::Data::Tag}
              )
            end

            app.get %r{^/rules(?:/)?([^/]+)?$} do
              requested_rules = if params[:captures] && params[:captures][0]
                params[:captures][0].split(',').uniq
              else
                nil
              end

              status 200
              resource_get(Flapjack::Data::Rule, 'rules', requested_rules,
                           :attributes       => ['id'],
                           :sort => :id)
            end

            app.put %r{^/rules/(.+)$} do
              rule_ids = params[:captures][0].split(',').uniq

              resource_put(Flapjack::Data::Rule, 'rules', rule_ids,
                :singular_links   => {'contact' => Flapjack::Data::Contact},
                :collection_links => {'tags'    => Flapjack::Data::Tag,
                                      'routes'  => Flapjack::Data::Route}
              )
              status 204
            end

            app.delete %r{^/rules/(.+)$} do
              rule_ids = params[:captures][0].split(',').uniq

              resource_delete(Flapjack::Data::Rule, rule_ids)
              status 204
            end
          end
        end
      end
    end
  end
end
