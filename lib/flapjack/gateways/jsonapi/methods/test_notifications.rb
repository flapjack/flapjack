#!/usr/bin/env ruby

require 'sinatra/base'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module TestNotifications

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Resources

            app.post %r{^/test_notifications/(checks|tags)/(.+)$} do
              # check_ids = params[:captures][0].split(',')

              # test_notifications = wrapped_params('test_notifications', false)
              # checks = Flapjack::Data::Check.find_by_ids!(*check_ids)

              # test_notifications.each do |wp|
              #   summary = wp['summary'] ||
              #             "Testing notifications to all contacts interested in #{checks.map(&:name).join(', ')}"
              #   Flapjack::Data::Event.test_notifications(
              #     config['processor_queue'] || 'events',
              #     checks, :summary => summary)
              # end
              # status 204
            end
          end
        end
      end
    end
  end
end