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
              # scheduled_maintenance_data, unwrap = wrapped_params('scheduled_maintenances')

              # # TODO check has_sorted_set linkages

              # scheduled_maintenances = resource_post(Flapjack::Data::ScheduledMaintenance,
              #   scheduled_maintenance_data,
              #   :attributes       => ['id', 'start_time', 'end_time', 'summary'],
              #   # :singular_links   => {'check' => Flapjack::Data::Check})
              # )

              # status 201
              # response.headers['Location'] = "#{base_url}/scheduled_maintenances/#{scheduled_maintenances.map(&:id).join(',')}"
              # scheduled_maintenances_as_json = Flapjack::Data::Check.as_jsonapi(unwrap, *scheduled_maintenances)
              # Flapjack.dump_json(:scheduled_maintenances => scheduled_maintenances_as_json)
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