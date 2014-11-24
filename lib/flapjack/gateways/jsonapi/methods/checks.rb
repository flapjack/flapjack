#!/usr/bin/env ruby

require 'sinatra/base'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module Checks

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Resources

            app.post '/checks' do
              status 201
              resource_post(Flapjack::Data::Check, 'checks',
                :attributes       => ['id', 'name', 'initial_failure_delay',
                                      'repeat_failure_delay', 'enabled'],
                :collection_links => {'tags' => Flapjack::Data::Tag})
            end

            app.get %r{^/checks(?:/)?(.+)?$} do
              requested_checks = if params[:captures] && params[:captures][0]
                params[:captures][0].split(',').uniq
              else
                nil
              end

              status 200
              resource_get(Flapjack::Data::Check, 'checks', requested_checks,
                           :attributes => ['id', 'name', 'initial_failure_delay',
                                           'repeat_failure_delay', 'enabled'],
                           :sort => 'name')
            end

            app.put %r{^/checks/(.+)$} do
              check_ids = params[:captures][0].split(',').uniq

              resource_put(Flapjack::Data::Check, 'checks', check_ids,
                :attributes       => ['name', 'initial_failure_delay',
                                      'repeat_failure_delay', 'enabled'],
                :collection_links => {'tags' => Flapjack::Data::Tag}
              )
              status 204
            end
          end
        end
      end
    end
  end
end
