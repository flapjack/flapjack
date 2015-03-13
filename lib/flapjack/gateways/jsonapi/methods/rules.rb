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

            app.class_eval do
              swagger_args = ['rules', Flapjack::Data::Rule]

              swagger_post(*swagger_args)
              swagger_get(*swagger_args)
              swagger_patch(*swagger_args)
              swagger_delete(*swagger_args)
            end

            app.post '/rules' do
              status 201
              resource_post(Flapjack::Data::Rule, 'rules')
            end

            app.get %r{^/rules(?:/)?([^/]+)?$} do
              requested_rules = if params[:captures] && params[:captures][0]
                params[:captures][0].split(',').uniq
              else
                nil
              end

              status 200
              resource_get(Flapjack::Data::Rule, 'rules', requested_rules,
                           :sort => :id)
            end

            app.patch %r{^/rules/(.+)$} do
              rule_ids = params[:captures][0].split(',').uniq

              resource_patch(Flapjack::Data::Rule, 'rules', rule_ids)
              status 204
            end

            app.delete %r{^/rules/(.+)$} do
              rule_ids = params[:captures][0].split(',').uniq

              # extra locking to allow rule destroy callback to work
              Flapjack::Data::Rule.lock(Flapjack::Data::Contact,
                Flapjack::Data::Medium, Flapjack::Data::Tag,
                Flapjack::Data::Route, Flapjack::Data::Check) do

                resource_delete(Flapjack::Data::Rule, rule_ids)
              end

              status 204
            end
          end
        end
      end
    end
  end
end
