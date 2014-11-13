#!/usr/bin/env ruby

require 'sinatra/base'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module UnscheduledMaintenances

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Resources

            app.post '/unscheduled_maintenances' do
              # unscheduled_maintenance_data, unwrap = wrapped_params('unscheduled_maintenances')

              # # TODO check has_sorted_set linkages

              # unscheduled_maintenances = resource_post(Flapjack::Data::UnscheduledMaintenance,
              #   scheduled_maintenance_data,
              #   :attributes       => ['id', 'start_time', 'end_time', 'summary'],
              #   # :singular_links   => {'check' => Flapjack::Data::Check})
              # )

              # status 201
              # response.headers['Location'] = "#{base_url}/unscheduled_maintenances/#{unscheduled_maintenances.map(&:id).join(',')}"
              # unscheduled_maintenances_as_json = Flapjack::Data::UnscheduledMaintenance.as_jsonapi(unwrap, *unscheduled_maintenances)
              # Flapjack.dump_json(:unscheduled_maintenances => unscheduled_maintenances_as_json)
            end

            app.put %r{^/unscheduled_maintenances/(.+)$} do
              # check_ids = params[:captures][0].split(',')

              # Flapjack::Data::Check.find_by_ids!(*check_ids).each do |check|
              #   apply_json_patch('unscheduled_maintenances') do |op, property, linked, value|
              #     case op
              #     when 'replace'
              #       if ['end_time'].include?(property)
              #         end_time = validate_and_parsetime(value)
              #         check.clear_unscheduled_maintenance(end_time.to_i)
              #       end
              #     end
              #   end
              # end

              # status 204
            end
          end
        end
      end
    end
  end
end