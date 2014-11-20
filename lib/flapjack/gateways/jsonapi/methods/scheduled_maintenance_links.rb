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

            app.post %r{^/scheduled_maintenances/(#{Flapjack::UUID_RE})/links/(check)$} do
              scheduled_maintenance_id = params[:captures][0]
              assoc_type               = params[:captures][1]

              resource_post_links(Flapjack::Data::ScheduledMaintenance,
                scheduled_maintenance_id, assoc_type,
                :singular_links   => {'check' => Flapjack::Data::Check},
              )
              status 204
            end

            app.get %r{^/scheduled_maintenances/(#{Flapjack::UUID_RE})/links/(check)} do
              scheduled_maintenance_id = params[:captures][0]
              assoc_type               = params[:captures][1]

              status 200
              resource_get_links(Flapjack::Data::ScheduledMaintenance,
                scheduled_maintenance_id, assoc_type,
                :singular_links   => {'check' => Flapjack::Data::Check}
              )
            end

            app.put %r{^/scheduled_maintenances/(#{Flapjack::UUID_RE})/links/(check)$} do
              scheduled_maintenance_id = params[:captures][0]
              assoc_type               = params[:captures][1]

              resource_put_links(Flapjack::Data::ScheduledMaintenance,
                scheduled_maintenance_id, assoc_type,
                :singular_links   => {'check' => Flapjack::Data::Check},
              )
              status 204
            end

            app.delete %r{^/scheduled_maintenances/(#{Flapjack::UUID_RE})/links/(check)$} do
              scheduled_maintenance_id = params[:captures][0]
              assoc_type               = params[:captures][1]

              assoc_klass = {'check' => Flapjack::Data::Check}[assoc_type]

              resource_delete_link(Flapjack::Data::ScheduledMaintenance,
                scheduled_maintenance_id, assoc_type, assoc_klass)
              status 204
            end
          end
        end
      end
    end
  end
end
