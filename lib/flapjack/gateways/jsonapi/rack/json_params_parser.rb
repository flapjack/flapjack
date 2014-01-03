#!/usr/bin/env ruby

require 'rack'

module Rack
  class JsonParamsParser < Struct.new(:app)
    def call(env)
      if env['rack.input'] and not input_parsed?(env) and type_match?(env)
        env['rack.request.form_input'] = env['rack.input']
        data = env['rack.input'].read
        env['rack.input'].rewind
        env['rack.request.form_hash'] = data.empty? ? {} : Oj.load(data)
      end
      app.call(env)
    end

    def input_parsed? env
      env['rack.request.form_input'].eql? env['rack.input']
    end

    def type_match? env
      type = env['CONTENT_TYPE'] and
        Flapjack::Gateways::API::JSON_REQUEST_MIME_TYPES.include?(type.split(/\s*[;,]\s*/, 2).first.downcase)
    end
  end
end
