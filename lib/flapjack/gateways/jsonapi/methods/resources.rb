#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/check'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module Resources

          RESOURCE_CLASSES = [
            Flapjack::Data::Check,
            Flapjack::Data::Contact,
            Flapjack::Data::Medium,
            Flapjack::Data::Rule,
            Flapjack::Data::ScheduledMaintenance,
            Flapjack::Data::Tag,
            Flapjack::Data::UnscheduledMaintenance
          ]

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Resources

            RESOURCE_CLASSES.each do |resource_class|
              endpoint = resource_class.jsonapi_type.pluralize.downcase

              app.class_eval do
                swagger_args = [endpoint, resource_class]

                swagger_wrappers(*swagger_args)
                swagger_post(*swagger_args)
                swagger_get(*swagger_args)
                swagger_patch(*swagger_args)
                swagger_delete(*swagger_args)
              end

              app.post "/#{endpoint}" do
                status 201
                resource_post(resource_class, endpoint)
              end

              app.get %r{^/#{endpoint}(?:/(.+))?$} do
                resource_id = params[:captures].nil? ? nil :
                                params[:captures].first
                status 200
                resource_get(resource_class, endpoint, resource_id)
              end

              app.patch %r{^/#{endpoint}(?:/(.+))?$} do
                resource_id = params[:captures].nil? ? nil :
                                params[:captures].first
                status 204
                resource_patch(resource_class, endpoint, resource_id)
              end

              app.delete %r{^/#{endpoint}(?:/(.+))?$} do
                resource_id = params[:captures].nil? ? nil :
                                params[:captures].first
                status 204

                if Flapjack::Data::Rule.eql?(resource_class)
                  # extra locking to allow rule destroy callback to work
                  Flapjack::Data::Rule.lock(Flapjack::Data::Contact,
                    Flapjack::Data::Medium, Flapjack::Data::Tag,
                    Flapjack::Data::Route, Flapjack::Data::Check) do

                    resource_delete(Flapjack::Data::Rule, resource_id)
                  end
                else
                  resource_delete(resource_class, resource_id)
                end
              end
            end
          end
        end
      end
    end
  end
end
