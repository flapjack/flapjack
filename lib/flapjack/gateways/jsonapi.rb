#!/usr/bin/env ruby

# A HTTP-based API server, which provides queries to determine the status of
# entities and the checks that are reported against them.
#
# There's a matching flapjack-diner gem at https://github.com/flpjck/flapjack-diner
# which consumes data from this API.

require 'time'

require 'sinatra/base'

require 'active_support/core_ext/string/inflections'

require 'flapjack/gateways/jsonapi/rack/json_params_parser'

%w[headers miscellaneous resources resource_links].each do |helper|
  require "flapjack/gateways/jsonapi/helpers/#{helper}"
end

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      include Flapjack::Utility

      JSON_REQUEST_MIME_TYPES = ['application/vnd.api+json', 'application/json', 'application/json-patch+json']
      # http://www.iana.org/assignments/media-types/application/vnd.api+json
      JSONAPI_MEDIA_TYPE = 'application/vnd.api+json; charset=utf-8'
      # http://tools.ietf.org/html/rfc6902
      JSON_PATCH_MEDIA_TYPE = 'application/json-patch+json; charset=utf-8'

      set :raise_errors, true
      set :show_exceptions, false

      set :protection, :except => :path_traversal

      use ::Rack::MethodOverride
      use Flapjack::Gateways::JSONAPI::Rack::JsonParamsParser

      class << self
        def start
          @logger.info "starting jsonapi - class"
        end
      end

      ['logger', 'config'].each do |class_inst_var|
        define_method(class_inst_var.to_sym) do
          self.class.instance_variable_get("@#{class_inst_var}")
        end
      end

      before do
        Sandstorm.redis ||= Flapjack.redis

        input = nil
        query_string = (request.query_string.respond_to?(:length) &&
                        request.query_string.length > 0) ? "?#{request.query_string}" : ""
        if logger.debug?
          input = env['rack.input'].read
          logger.debug("#{request.request_method} #{request.path_info}#{query_string} Headers: #{headers.inspect}, Body: #{input}")
        elsif logger.info?
          input = env['rack.input'].read
          input_short = input.gsub(/\n/, '').gsub(/\s+/, ' ')
          logger.info("#{request.request_method} #{request.path_info}#{query_string} #{input_short[0..80]}")
        end
        env['rack.input'].rewind unless input.nil?
      end

      after do
        return if response.status == 500

        query_string = (request.query_string.respond_to?(:length) &&
                        request.query_string.length > 0) ? "?#{request.query_string}" : ""
        if logger.debug?
          body_debug = case
          when response.body.respond_to?(:each)
            response.body.each_with_index {|r, i| "body[#{i}]: #{r}"}.join(', ')
          else
            response.body.to_s
          end
          headers_debug = response.headers.to_s
          logger.debug("Returning #{response.status} for #{request.request_method} " +
            "#{request.path_info}#{query_string}, headers: #{headers_debug}, body: #{body_debug}")
        elsif logger.info?
          logger.info("Returning #{response.status} for #{request.request_method} " +
            "#{request.path_info}#{query_string}")
        end
      end

      options '*' do
        cors_headers
        204
      end

      # The following catch-all routes act as impromptu filters for their method types
      get '*' do
        content_type JSONAPI_MEDIA_TYPE
        cors_headers
        pass
      end

      # bare 'params' may have splat/captures for regex route, see
      # https://github.com/sinatra/sinatra/issues/453
      post '*' do
        halt(405) unless request.params.empty? || is_json_request? || is_jsonapi_request?
        content_type JSONAPI_MEDIA_TYPE
        cors_headers
        pass
      end

      put '*' do
        halt(405) unless request.params.empty? || is_json_request? || is_jsonapi_request?
        content_type JSONAPI_MEDIA_TYPE
        cors_headers
        pass
      end

      patch '*' do
        halt(405) unless is_jsonpatch_request?
        content_type JSONAPI_MEDIA_TYPE
        cors_headers
        pass
      end

      delete '*' do
        cors_headers
        pass
      end

      # hacky, but trying to avoid too much boilerplate -- links paths
      # must be before regular ones to avoid greedy path captures
      %w[check_links checks contact_links contacts medium_links media
         route_links routes rule_links rules tag_links tags
         scheduled_maintenance_links scheduled_maintenances
         unscheduled_maintenance_links unscheduled_maintenances
         reports searches test_notifications].each do |method|

        require "flapjack/gateways/jsonapi/methods/#{method}"
        eval "register Flapjack::Gateways::JSONAPI::Methods::#{method.camelize}"
      end

      error Sandstorm::LockNotAcquired do
        # TODO
      end

      error Sandstorm::Records::Errors::RecordNotFound do
        e = env['sinatra.error']
        type = e.klass.name.split('::').last
        err(404, "could not find #{type} record, id: '#{e.id}'")
      end

      error Sandstorm::Records::Errors::RecordsNotFound do
        e = env['sinatra.error']
        type = e.klass.name.split('::').last
        err(404, "could not find #{type} records, ids: '#{e.ids.join(',')}'")
      end

      error do
        e = env['sinatra.error']
        err(response.status, "#{e.class} - #{e.message}")
      end

    end
  end
end
