#!/usr/bin/env ruby

require 'rack'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Middleware
        class JsonParamsParser < Struct.new(:app)
          def call(env)
            t = type(env)
            if ['POST', 'PATCH', 'DELETE'].include?(env["REQUEST_METHOD"]) &&
              env['rack.input'] && !input_parsed?(env) && type_match?(t)

              env['rack.request.form_input'] = env['rack.input']
              json_data = env['rack.input'].read
              env['rack.input'].rewind
              data = json_data.empty? ? {} : Flapjack.load_json(json_data)
              env['rack.request.form_hash'] = data
            end
            app.call(env)
          end

          def input_parsed? env
            env['rack.request.form_input'].eql?(env['rack.input'])
          end

          def type(env)
            return if env['CONTENT_TYPE'].nil?
            env['CONTENT_TYPE'].split(/\s*[;,]\s*/, 2).first
          end

          def type_match?(t)
            Flapjack::Gateways::JSONAPI::JSONAPI_MEDIA_TYPE.eql?(t)
          end
        end
      end
    end
  end
end
