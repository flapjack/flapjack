#!/usr/bin/env ruby

require 'sinatra/base'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module ScheduledMaintenances

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Resources

            app.class_eval do
              swagger_args = ['scheduled_maintenances',
                              Flapjack::Data::ScheduledMaintenance]

              swagger_post(*swagger_args)
              swagger_get(*swagger_args)
              swagger_put(*swagger_args)
              swagger_delete(*swagger_args)
            end

            app.post '/scheduled_maintenances' do
              status 201
              scheduled_maintenances = resource_post(Flapjack::Data::ScheduledMaintenance,
                'scheduled_maintenances')
            end

            app.get %r{^/scheduled_maintenances(?:/)?(.+)?$} do
              requested_scheduled_maintenances = if params[:captures] && params[:captures][0]
                params[:captures][0].split(',').uniq
              else
                nil
              end

              status 200
              resource_get(Flapjack::Data::ScheduledMaintenance,
                           'scheduled_maintenances',
                           requested_scheduled_maintenances,
                           :sort => :timestamp)
            end

            app.delete %r{^/scheduled_maintenances/(.+)$} do
              scheduled_maintenance_ids = params[:captures][0].split(',').uniq
              resource_delete(Flapjack::Data::ScheduledMaintenance, scheduled_maintenance_ids)
              status 204
            end

          end
        end
      end
    end
  end
end