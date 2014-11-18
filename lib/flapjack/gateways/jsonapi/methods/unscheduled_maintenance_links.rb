#!/usr/bin/env ruby

require 'sinatra/base'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module UnscheduledMaintenanceLinks

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::ResourceLinks

            app.post %r{^/unscheduled_maintenances/(#{Flapjack::UUID_RE})/links/(check)$} do
              unscheduled_maintenance_id = params[:captures][0]
              assoc_type                 = params[:captures][1]

              resource_post_links(Flapjack::Data::UnscheduledMaintenance,
                unscheduled_maintenance_id, assoc_type,
                :singular_links   => {'check' => Flapjack::Data::Check}
              )
              status 204
            end

            app.get %r{^/unscheduled_maintenances/(#{Flapjack::UUID_RE})/links/(check)} do
              unscheduled_maintenance_id = params[:captures][0]
              assoc_type                 = params[:captures][1]

              resource_get_links(Flapjack::Data::UnscheduledMaintenance,
                unscheduled_maintenance_id, assoc_type,
                :singular_links   => {'check' => Flapjack::Data::Check}
              )
              status 200
            end

            app.put %r{^/unscheduled_maintenances/(#{Flapjack::UUID_RE})/links/(check)$} do
              unscheduled_maintenance_id = params[:captures][0]
              assoc_type                 = params[:captures][1]

              resource_put_links(Flapjack::Data::UnscheduledMaintenance,
                unscheduled_maintenance_id, assoc_type,
                :singular_links   => {'check' => Flapjack::Data::Check}
              )
              status 204
            end

            app.delete %r{^/unscheduled_maintenances/(#{Flapjack::UUID_RE})/links/(check)/(.+)$} do
              unscheduled_maintenance_id = params[:captures][0]
              assoc_type                 = params[:captures][1]
              assoc_ids  = params[:captures][2].split(',').uniq

              assoc_klass = {'check' => Flapjack::Data::Check}[assoc_type]

              resource_delete_links(Flapjack::Data::UnscheduledMaintenance,
                unscheduled_maintenance_id, assoc_type, assoc_klass, assoc_ids)
              status 204
            end
          end
        end
      end
    end
  end
end
