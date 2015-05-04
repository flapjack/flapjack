#!/usr/bin/env ruby

require 'rack'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Middleware
        class RequestTimestamp < Struct.new(:app)
          def call(env)
            env['request_timestamp'] = Time.now
            app.call(env)
          end
        end
      end
    end
  end
end
