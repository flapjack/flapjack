#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/event'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module TestNotifications

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Resources

            # not allowing a single request to send notifications for all
            # checks -- design choice, to avoid unintended spam
            app.post %r{^/test_notifications/(.+)$} do
              check_ids = params[:captures][0].split(',')

              test_notifications, unwrap = wrapped_params('test_notifications',
                                                          :error_on_nil => false)
              checks = Flapjack::Data::Check.find_by_ids!(*check_ids)

              # assume single notification with default summary if none sent
              test_notifications = [{}] if test_notifications.empty?

              test_notifications.each do |tn|
                tn['summary'] ||=
                  'Testing notifications to everyone interested in ' +
                  checks.map(&:name).join(', ')

                Flapjack::Data::Event.test_notifications(
                  config['processor_queue'] || 'events',
                  checks, :summary => tn['summary'])

                tn['links'] = {'checks' => checks.map(&:id)}
              end

              status 201
              # No Location headers, as the returned 'resources' don't have
              # relevant URLs
              Flapjack.dump_json(:test_notifications => test_notifications)
            end
          end
        end
      end
    end
  end
end