#!/usr/bin/env ruby

# A HTTP-based API server, which provides queries to determine the status of
# entities and the checks that are reported against them.
#
# There's a matching flapjack-diner gem at https://github.com/flpjck/flapjack-diner
# which consumes data from this API.

require 'time'

require 'sinatra/base'

require 'flapjack/gateways/jsonapi/rack/json_params_parser'

require 'flapjack/gateways/jsonapi/check_methods'
require 'flapjack/gateways/jsonapi/contact_methods'
require 'flapjack/gateways/jsonapi/entity_methods'
require 'flapjack/gateways/jsonapi/medium_methods'
require 'flapjack/gateways/jsonapi/notification_rule_methods'
require 'flapjack/gateways/jsonapi/notification_rule_state_methods'
require 'flapjack/gateways/jsonapi/pagerduty_credential_methods'
require 'flapjack/gateways/jsonapi/report_methods'

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      include Flapjack::Utility

      JSON_REQUEST_MIME_TYPES = ['application/vnd.api+json', 'application/json', 'application/json-patch+json']
      # http://www.iana.org/assignments/media-types/application/vnd.api+json
      JSONAPI_MEDIA_TYPE = 'application/vnd.api+json; charset=utf-8'
      # http://tools.ietf.org/html/rfc6902
      JSON_PATCH_MEDIA_TYPE = 'application/json-patch+json; charset=utf-8'

      class RecordNotFound < RuntimeError
        attr_reader :klass, :id
        def initialize(k, i)
          @klass = k
          @id    = i
        end
      end

      set :raise_errors, true
      set :show_exceptions, false

      use ::Rack::MethodOverride
      use Flapjack::Gateways::JSONAPI::Rack::JsonParamsParser

      class << self
        def start
          @logger.info "starting jsonapi - class"

          if @config && @config['access_log']
            access_logger = Flapjack::AsyncLogger.new(@config['access_log'])
            use Flapjack::CommonLogger, access_logger
          end

          @base_url = @config['base_url']
          dummy_url = "http://api.example.com"
          if @base_url
            @base_url = $1 if @base_url.match(/^(.+)\/$/)
          else
            @logger.error "base_url must be a valid http or https URI (not configured), setting to dummy value (#{dummy_url})"
            # FIXME: at this point I'd like to stop this pikelet without bringing down the whole
            @base_url = dummy_url
          end
          if (@base_url =~ /^#{URI::regexp(%w(http https))}$/).nil?
            @logger.error "base_url must be a valid http or https URI (#{@base_url}), setting to dummy value (#{dummy_url})"
            # FIXME: at this point I'd like to stop this pikelet without bringing down the whole
            # flapjack process
            # For now, set a dummy value
            @base_url = dummy_url
          end
        end
      end

      ['logger', 'config'].each do |class_inst_var|
        define_method(class_inst_var.to_sym) do
          self.class.instance_variable_get("@#{class_inst_var}")
        end
      end

      before do
        input = nil
        query_string = (request.query_string.respond_to?(:length) &&
                        request.query_string.length > 0) ? "?#{request.query_string}" : ""
        if logger.debug?
          input = env['rack.input'].read
          logger.debug("#{request.request_method} #{request.path_info}#{query_string} #{input}")
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
          logger.debug("Returning #{response.status} for #{request.request_method} " +
            "#{request.path_info}#{query_string}, body: #{body_debug}")
        elsif logger.info?
          logger.info("Returning #{response.status} for #{request.request_method} " +
            "#{request.path_info}#{query_string}")
        end
      end

      # the following should add the cors headers to every request, but is no work
      #register Sinatra::CrossOrigin
      #
      #configure do
      #  enable :cross_origin
      #end
      #set :allow_origin, :any
      #set :allow_methods, [:get, :post, :put, :patch, :delete, :options]

      module Helpers

        def cors_headers
          allow_headers  = %w(* Content-Type Accept AUTHORIZATION Cache-Control)
          allow_methods  = %w(GET POST PUT PATCH DELETE OPTIONS)
          expose_headers = %w(Cache-Control Content-Language Content-Type Expires Last-Modified Pragma)
          cors_headers   = {
            'Access-Control-Allow-Origin'   => '*',
            'Access-Control-Allow-Methods'  => allow_methods.join(', '),
            'Access-Control-Allow-Headers'  => allow_headers.join(', '),
            'Access-Control-Expose-Headers' => expose_headers.join(', '),
            'Access-Control-Max-Age'        => '1728000'
          }
          headers(cors_headers)
        end

        def err(status, *msg)
          msg_str = msg.join(", ")
          logger.info "Error: #{msg_str}"
          [status, {}, {:errors => msg}.to_json]
        end

        def is_json_request?
          Flapjack::Gateways::JSONAPI::JSON_REQUEST_MIME_TYPES.include?(request.content_type.split(/\s*[;,]\s*/, 2).first)
        end

        def is_jsonapi_request?
          return false if request.content_type.nil?
          'application/vnd.api+json'.eql?(request.content_type.split(/\s*[;,]\s*/, 2).first)
        end

        def is_jsonpatch_request?
          return false if request.content_type.nil?
          'application/json-patch+json'.eql?(request.content_type.split(/\s*[;,]\s*/, 2).first)
        end

        def wrapped_params(name, error_on_nil = true)
          result = params[name.to_sym]
          if result.nil?
            if error_on_nil
              logger.debug("No '#{name}' object found in the following supplied JSON:")
              logger.debug(request.body.is_a?(StringIO) ? request.body.read : request.body)
              halt err(403, "No '#{name}' object received")
            else
              result = [{}]
            end
          end
          unless result.is_a?(Array)
            halt err(403, "The received '#{name}'' object is not an Array")
          end
          result
        end

        def apply_json_patch(object_path, &block)
          ops = params[:ops]

          if ops.nil? || !ops.is_a?(Array)
            halt err(400, "Invalid JSON-Patch request")
          end

          ops.each do |operation|
            linked = nil
            property = nil

            op = operation['op']
            operation['path'] =~ /\A\/#{object_path}\/0\/([^\/]+)(?:\/([^\/]+)(?:\/([^\/]+))?)?\z/
            if 'links'.eql?($1)
              linked = $2

              value = case op
              when 'add'
                operation['value']
              when 'remove'
                $3
              end
            elsif 'replace'.eql?(op)
              property = $1
              value = operation['value']
            else
              next
            end

            yield(op, property, linked, value)
          end
        end

        # NB: casts to UTC before converting to a timestamp
        def validate_and_parsetime(value)
          return unless value
          Time.iso8601(value).getutc.to_i
        rescue ArgumentError => e
          logger.error "Couldn't parse time from '#{value}'"
          nil
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
        halt(405) unless request.params.empty? || is_json_request? || is_jsonapi_request
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

      register Flapjack::Gateways::JSONAPI::CheckMethods
      register Flapjack::Gateways::JSONAPI::ContactMethods
      register Flapjack::Gateways::JSONAPI::EntityMethods
      register Flapjack::Gateways::JSONAPI::MediumMethods
      register Flapjack::Gateways::JSONAPI::NotificationRuleMethods
      register Flapjack::Gateways::JSONAPI::NotificationRuleStateMethods
      register Flapjack::Gateways::JSONAPI::PagerdutyCredentialMethods
      register Flapjack::Gateways::JSONAPI::ReportMethods

      not_found do
        err(404, "not routable")
      end

      error Sandstorm::LockNotAcquired do
        # TODO
      end

      error Sandstorm::Errors::RecordNotFound do
        e = env['sinatra.error']
        type = e.klass.name.split('::').last
        err(404, "could not find #{type} record, id: '#{e.id}'")
      end

      error Sandstorm::Errors::RecordsNotFound do
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
