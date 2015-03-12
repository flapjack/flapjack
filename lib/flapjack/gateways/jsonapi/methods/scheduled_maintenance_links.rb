#!/usr/bin/env ruby

require 'sinatra/base'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module ScheduledMaintenanceLinks

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::ResourceLinks

            app.class_eval do
              swagger_args = ['scheduled_maintenances',
                              Flapjack::Data::ScheduledMaintenance,
                              {'check' => Flapjack::Data::Check}]

              swagger_post_links(*swagger_args)
              swagger_get_links(*swagger_args)
              swagger_put_links(*swagger_args)
              swagger_delete_links(*swagger_args)
            end

            app.post %r{^/scheduled_maintenances/(#{Flapjack::UUID_RE})/links/(check)$} do
              scheduled_maintenance_id = params[:captures][0]
              assoc_type               = params[:captures][1]

              resource_post_links(Flapjack::Data::ScheduledMaintenance,
                'scheduled_maintenances', scheduled_maintenance_id, assoc_type)
              status 204
            end

            app.get %r{^/scheduled_maintenances/(#{Flapjack::UUID_RE})/(check)} do
              scheduled_maintenance_id = params[:captures][0]
              assoc_type               = params[:captures][1]

              status 200
              resource_get_links(Flapjack::Data::ScheduledMaintenance,
                'scheduled_maintenances', scheduled_maintenance_id, assoc_type)
            end

            app.put %r{^/scheduled_maintenances/(#{Flapjack::UUID_RE})/links/(check)$} do
              scheduled_maintenance_id = params[:captures][0]
              assoc_type               = params[:captures][1]

              resource_put_links(Flapjack::Data::ScheduledMaintenance,
                'scheduled_maintenances', scheduled_maintenance_id, assoc_type)
              status 204
            end

            app.delete %r{^/scheduled_maintenances/(#{Flapjack::UUID_RE})/links/(check)$} do
              scheduled_maintenance_id = params[:captures][0]
              assoc_type               = params[:captures][1]

              resource_delete_link(Flapjack::Data::ScheduledMaintenance,
                'scheduled_maintenances', scheduled_maintenance_id, assoc_type)
              status 204
            end
          end
        end
      end
    end
  end
end
