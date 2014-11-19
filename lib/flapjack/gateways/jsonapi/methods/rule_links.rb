#!/usr/bin/env ruby

require 'sinatra/base'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module RuleLinks

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::ResourceLinks

            app.post %r{^/rules/(#{Flapjack::UUID_RE})/links/(contact|routes|tags)$} do
              rule_id    = params[:captures][0]
              assoc_type = params[:captures][1]

              resource_post_links(Flapjack::Data::Rule, rule_id, assoc_type,
                :singular_links   => {'contact' => Flapjack::Data::Contact},
                :collection_links => {'routes'  => Flapjack::Data::Route,
                                      'tags'    => Flapjack::Data::Tag})
              status 204
            end

            app.get %r{^/rules/(#{Flapjack::UUID_RE})/links/(contact|routes|tags)} do
              rule_id    = params[:captures][0]
              assoc_type = params[:captures][1]

              status 200
              resource_get_links(Flapjack::Data::Rule, rule_id, assoc_type,
                :singular_links   => {'contact' => Flapjack::Data::Contact},
                :collection_links => {'routes'  => Flapjack::Data::Route,
                                      'tags'    => Flapjack::Data::Tag})
            end

            app.put %r{^/rules/(#{Flapjack::UUID_RE})/links/(contact|routes|tags)$} do
              rule_id    = params[:captures][0]
              assoc_type = params[:captures][1]

              resource_put_links(Flapjack::Data::Rule, rule_id, assoc_type,
                :singular_links   => {'contact' => Flapjack::Data::Contact},
                :collection_links => {'routes'  => Flapjack::Data::Route,
                                      'tags'    => Flapjack::Data::Tag})
              status 204
            end

            app.delete %r{^/rules/(#{Flapjack::UUID_RE})/links/(contact)$} do
              rule_id    = params[:captures][0]
              assoc_type = params[:captures][1]

              assoc_klass = {'contact' => Flapjack::Data::Contact}[assoc_type]

              resource_delete_link(Flapjack::Data::Rule, rule_id, assoc_type,
                assoc_klass)
              status 204
            end

            app.delete %r{^/rules/(#{Flapjack::UUID_RE})/links/(routes|tags)/(.+)$} do
              rule_id    = params[:captures][0]
              assoc_type = params[:captures][1]
              assoc_ids  = params[:captures][2].split(',').uniq

              assoc_klass = {'routes' => Flapjack::Data::Route,
                             'tags'   => Flapjack::Data::Tag}[assoc_type]

              resource_delete_links(Flapjack::Data::Rule, rule_id,
                assoc_type, assoc_klass, assoc_ids)
              status 204
            end

          end
        end
      end
    end
  end
end
