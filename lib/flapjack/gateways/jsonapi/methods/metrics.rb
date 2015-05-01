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

            app.get %r{^/metrics$} do
              fields = params[:fields].nil?  ? nil : params[:fields].split(',')
              whitelist = Flapjack::Data::Metrics.jsonapi_attributes[:get]

              jsonapi_fields = if fields.nil?
                whitelist
              else
                Set.new(fields).keep_if {|f| whitelist.include?(f) }.to_a
              end

              metrics = Flapjack::Data::Metrics.new
              result = Hash[ *(jsonapi_fields.collect{|f| [f, metrics.send(f.to_sym)]}) ]
              Flapjack.dump_json(result)
            end
          end

        end
      end
    end
  end
end
