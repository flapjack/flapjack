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

            app.class_eval do
              swagger_args = ['rules',
                              Flapjack::Data::Rule,
                              {'contact' => Flapjack::Data::Contact,
                               'media'   => Flapjack::Data::Medium,
                               'tags'    => Flapjack::Data::Tag}]

              swagger_multi_args = ['rules',
                              Flapjack::Data::Rule,
                              {'media'   => Flapjack::Data::Medium,
                               'tags'    => Flapjack::Data::Tag}]

              swagger_post_links(*swagger_multi_args)
              swagger_get_links(*swagger_args)
              swagger_patch_links(*swagger_args)
              swagger_delete_links(*swagger_multi_args)
            end

            app.post %r{^/rules/(#{Flapjack::UUID_RE})/links/(contact|media|tags)$} do
              rule_id    = params[:captures][0]
              assoc_type = params[:captures][1]

              resource_post_links(Flapjack::Data::Rule, 'rules', rule_id, assoc_type)
              status 204
            end

            app.get %r{^/rules/(#{Flapjack::UUID_RE})/(?:links/)?(contact|media|tags)} do
              rule_id    = params[:captures][0]
              assoc_type = params[:captures][1]

              status 200
              resource_get_links(Flapjack::Data::Rule, 'rules', rule_id, assoc_type)
            end

            app.patch %r{^/rules/(#{Flapjack::UUID_RE})/links/(contact|media|tags)$} do
              rule_id    = params[:captures][0]
              assoc_type = params[:captures][1]

              resource_patch_links(Flapjack::Data::Rule, 'rules', rule_id, assoc_type)
              status 204
            end

            app.delete %r{^/rules/(#{Flapjack::UUID_RE})/links/(media|tags)$} do
              rule_id    = params[:captures][0]
              assoc_type = params[:captures][1]

              resource_delete_links(Flapjack::Data::Rule, 'rules', rule_id,
                assoc_type)
              status 204
            end

          end
        end
      end
    end
  end
end
