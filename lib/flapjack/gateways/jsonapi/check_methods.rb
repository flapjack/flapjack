#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/gateways/jsonapi/entity_check_methods_helpers'

# NB: documentation changes required, this now uses individual check ids rather
# than v1's 'entity_name:check_name' pseudo-id

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      module CheckMethods

        module Helpers
        end

        def self.registered(app)
          app.helpers Flapjack::Gateways::JSONAPI::Helpers
          # app.helpers Flapjack::Gateways::JSONAPI::CheckMethods::Helpers
          app.helpers Flapjack::Gateways::JSONAPI::EntityCheckMethods::Helpers

          app.post %r{^/scheduled_maintenances/checks/([^/]+)$} do
            create_scheduled_maintenances(params[:captures][0].split(','))
          end

          # NB this does not acknowledge a specific failure event, just
          # the entity-check as a whole
          app.post %r{^/unscheduled_maintenances/checks/([^/]+)$} do
            create_unscheduled_maintenances(params[:captures][0].split(','))
          end

          app.patch %r{^/unscheduled_maintenances/checks/([^/]+)$} do
            update_unscheduled_maintenances(params[:captures][0].split(','))
          end

          app.delete %r{^/scheduled_maintenances/checks/([^/]+)$} do
            start_time = validate_and_parsetime(params[:start_time])
            halt( err(403, "start time must be provided") ) unless start_time

            delete_scheduled_maintenances(start_time, params[:captures][0].split(','))
          end

          app.post %r{^/test_notifications/checks/([^/]+)$} do
            create_test_notifications(params[:captures][0].split(','))
          end

        end

      end

    end

  end

end
