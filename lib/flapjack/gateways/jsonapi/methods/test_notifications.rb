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

            app.post '/test_notifications' do
              test_notifications, unwrap = wrapped_params('test_notifications',
                                                          :error_on_nil => true)

              checks_by_index = {}

              test_notifications.each_with_index do |tn, i|
                halt(400, "Invalid check link data") unless tn.has_key?('links') &&
                  tn['links'].has_key?('checks') &&
                  tn['links']['checks'].is_a?(Array) &&
                  tn['links']['checks'].all? {|c| c.is_a?(String)}

                checks_by_index[i] = Flapjack::Data::Check.find_by_ids!(*tn['links']['checks'])
              end

              test_notifications.each_with_index do |tn, i|
                checks = checks_by_index[i]

                tn['summary'] ||=
                  'Testing notifications to everyone interested in ' +
                  checks.map(&:name).join(', ')

                Flapjack::Data::Event.test_notifications(
                  config['processor_queue'] || 'events',
                  checks, :summary => tn['summary'])
              end

              status 201
              # No Location headers, as the returned 'resources' don't have
              # relevant URLs
              ret = unwrap ? test_notifications.first : test_notifications
              Flapjack.dump_json(:test_notifications => ret)
            end

          end
        end
      end
    end
  end
end