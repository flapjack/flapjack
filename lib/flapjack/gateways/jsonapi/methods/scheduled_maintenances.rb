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

            app.post '/scheduled_maintenances' do
              scheduled_maintenance_data, unwrap = wrapped_params('scheduled_maintenances')

              # TODO: link_aliases handling in validate_data
              scheduled_maintenances = resource_post(Flapjack::Data::ScheduledMaintenance,
                scheduled_maintenance_data,
                :attributes       => ['id', 'start_time', 'end_time', 'summary'],
                :singular_links   => {'check' => Flapjack::Data::Check},
                :link_aliases     => {'check' => ['check_by_start', 'check_by_end']}
              )

              status 201
              response.headers['Location'] = "#{base_url}/scheduled_maintenances/#{scheduled_maintenances.map(&:id).join(',')}"
              scheduled_maintenances_as_json = Flapjack::Data::ScheduledMaintenance.as_jsonapi(unwrap, *scheduled_maintenances)
              Flapjack.dump_json(:scheduled_maintenances => scheduled_maintenances_as_json)
            end

            app.get %r{^/scheduled_maintenances(?:/)?(.+)?$} do
              requested_scheduled_maintenances = if params[:captures] && params[:captures][0]
                params[:captures][0].split(',').uniq
              else
                nil
              end

              status 200
              resource_get(Flapjack::Data::ScheduledMaintenance,
                           requested_scheduled_maintenances,
                           'scheduled_maintenances',
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