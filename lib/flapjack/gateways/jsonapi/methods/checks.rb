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
              checks_data, unwrap = wrapped_params('checks')

              checks = resource_post(Flapjack::Data::Check, checks_data,
                :attributes       => ['id', 'name', 'initial_failure_delay',
                                      'repeat_failure_delay', 'enabled'],
                :collection_links => {'tags' => Flapjack::Data::Tag})

              status 201
              response.headers['Location'] = "#{base_url}/checks/#{checks.map(&:id).join(',')}"
              checks_as_json = Flapjack::Data::Check.as_jsonapi(unwrap, *checks)
              Flapjack.dump_json(:checks => checks_as_json)
            end

            app.get %r{^/checks(?:/)?(.+)?$} do
              requested_checks = if params[:captures] && params[:captures][0]
                params[:captures][0].split(',').uniq
              else
                nil
              end

              unwrap = !requested_checks.nil? && (requested_checks.size == 1)

              checks, meta = if requested_checks
                requested = Flapjack::Data::Check.find_by_ids!(*requested_checks)

                if requested.empty?
                  raise Flapjack::Gateways::JSONAPI::RecordsNotFound.new(Flapjack::Data::Check, requested_checks)
                end

                [requested, {}]
              else
                paginate_get(Flapjack::Data::Check.sort(:name, :order => 'alpha'),
                  :total => Flapjack::Data::Check.count, :page => params[:page],
                  :per_page => params[:per_page])
              end

              status 200
              checks_as_json = Flapjack::Data::Check.as_jsonapi(unwrap, *checks)
              Flapjack.dump_json({:checks => checks_as_json}.merge(meta))
            end

            app.put %r{^/checks/(.+)$} do
              check_ids = params[:captures][0].split(',').uniq
              checks_data, _ = wrapped_params('checks')

              resource_put(Flapjack::Data::Check, check_ids, checks_data,
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
