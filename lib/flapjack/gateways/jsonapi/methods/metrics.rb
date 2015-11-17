#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/metrics'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module Metrics

          # module Helpers
          # end

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Resources
            # app.helpers Flapjack::Gateways::JSONAPI::Methods::Metrics::Helpers

            app.class_eval do

              swagger_path "/metrics" do
                operation :get do
                  key :description, "Get metrics"
                  key :operationId, "get_metrics"
                  key :produces, [Flapjack::Gateways::JSONAPI.media_type_produced]
                  parameter do
                    key :name, :fields
                    key :in, :query
                    key :description, 'Comma-separated list of fields to return'
                    key :required, false
                    key :type, :string
                  end
                  response 200 do
                    key :description, "GET metrics response"
                    schema do
                      key :'$ref', :data_Metrics
                    end
                  end
                end
              end
            end

            app.get %r{^/metrics$} do
              fields = params[:fields]
              fields = [fields] unless fields.nil? || fields.is_a?(Array)

              whitelist = Flapjack::Data::Metrics.jsonapi_methods[:get].attributes

              jsonapi_fields = if fields.nil?
                whitelist
              else
                Set.new(fields).keep_if {|f| whitelist.include?(f.to_sym) }.to_a
              end

              metrics = Flapjack::Data::Metrics.new
              result = Hash[ *(jsonapi_fields.collect{|f| [f, metrics.send(f.to_sym)]}.flatten) ]
              Flapjack.dump_json(:data => {
                :id => SecureRandom.uuid,
                :type => 'metrics',
                :attributes => result
              })
            end
          end
        end
      end
    end
  end
end
