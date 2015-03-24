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

            app.post %r{/test_notifications/(?:(checks)/(.+)|(tags)/(.+))$} do
              test_notifications, unwrap = wrapped_params('test_notifications',
                                                          :error_on_nil => true)

              resource = params[:captures][0] || params[:captures][2]
              resource_id = params[:captures][0].nil? ? params[:captures][3] :
                                                        params[:captures][1]

              checks, unwrap = case resource
              when 'checks'
                [[Flapjack::Data::Check.find_by_id!(resource_id)], true]
              when 'tags'
                [Flapjack::Data::Tag.find_by_id!(resource_id).checks, false]
              end

              check_names = checks.map(&:name)

              test_notifications.each do |tn|
                tn['summary'] ||=
                  'Testing notifications to everyone interested in ' +
                  check_names.join(', ')

                Flapjack::Data::Event.test_notifications(
                  config['processor_queue'] || 'events',
                  checks, :summary => tn['summary'])
              end

              status 201
              # No Location headers, as the returned 'resources' don't have
              # relevant URLs
              ret = unwrap && (test_notifications.size == 1) ? test_notifications.first : test_notifications
              Flapjack.dump_json(:data => {:test_notifications => ret})
            end

          end
        end
      end
    end
  end
end