#!/usr/bin/env ruby

require 'rack'

# Hat-tip to https://github.com/glasnt for the suggestion

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Middleware
        class ArrayParamFixer < Struct.new(:app)
          def call(env)
            if (env["REQUEST_METHOD"] == 'GET') && env["rack.request.query_string"].nil?
              qs = env["QUERY_STRING"]
              fixed_qs = qs.to_s.sub(/^filter=/, "filter[]=")
                                .gsub(/&filter=/, "&filter[]=")

              env["rack.request.query_string"] = qs # avoid Rack re-parsing it
              env["rack.request.query_hash"]   = ::Rack::Utils.parse_nested_query(fixed_qs)
            end
            app.call(env)
          end
        end
      end
    end
  end
end
