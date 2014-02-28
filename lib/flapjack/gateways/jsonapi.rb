#!/usr/bin/env ruby

# A HTTP-based API server, which provides queries to determine the status of
# entities and the checks that are reported against them.
#
# There's a matching flapjack-diner gem at https://github.com/flpjck/flapjack-diner
# which consumes data from this API.

require 'time'

require 'rack/fiber_pool'
require 'sinatra/base'

require 'flapjack/rack_logger'
require 'flapjack/redis_pool'

require 'flapjack/gateways/jsonapi/rack/json_params_parser'

require 'flapjack/gateways/jsonapi/contact_methods'
require 'flapjack/gateways/jsonapi/entity_methods'
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

      class ContactNotFound < RuntimeError
        attr_reader :contact_id
        def initialize(contact_id)
          @contact_id = contact_id
        end
      end

      class ContactsNotFound < RuntimeError
        attr_reader :contact_ids
        def initialize(contact_ids)
          @contact_ids = contact_ids
        end
      end

      class NotificationRuleNotFound < RuntimeError
        attr_reader :rule_id
        def initialize(rule_id)
          @rule_id = rule_id
        end
      end

      class EntityNotFound < RuntimeError
        attr_reader :entity
        def initialize(entity)
          @entity = entity
        end
      end

      class EntitiesNotFound < RuntimeError
        attr_reader :entity_ids
        def initialize(entity_ids)
          @entity_ids = entity_ids
        end
      end

      class EntityCheckNotFound < RuntimeError
        attr_reader :entity, :check
        def initialize(entity, check)
          @entity = entity
          @check = check
        end
      end

      class ResourceLocked < RuntimeError
        attr_reader :resource
        def initialize(resource)
          @resource = resource
        end
      end

      set :dump_errors, false

      rescue_error = Proc.new {|status, exception, request_info, *msg|
        if !msg || msg.empty?
          trace = exception.backtrace.join("\n")
          msg = "#{exception.class} - #{exception.message}"
          msg_str = "#{msg}\n#{trace}"
        else
          msg_str = msg.join(", ")
        end
        case
        when status < 500
          @logger.warn "Error: #{msg_str}"
        else
          @logger.error "Error: #{msg_str}"
        end

        response_body = {:errors => msg}.to_json

        query_string = (request_info[:query_string].respond_to?(:length) &&
                        request_info[:query_string].length > 0) ? "?#{request_info[:query_string]}" : ""
        if @logger.debug?
          @logger.debug("Returning #{status} for #{request_info[:request_method]} " +
            "#{request_info[:path_info]}#{query_string}, body: #{response_body}")
        elsif @logger.info?
          @logger.info("Returning #{status} for #{request_info[:request_method]} " +
            "#{request_info[:path_info]}#{query_string}")
        end

        [status, {}, response_body]
      }

      rescue_exception = Proc.new {|env, e|
        request_info = {
          :path_info      => env['REQUEST_PATH'],
          :request_method => env['REQUEST_METHOD'],
          :query_string   => env['QUERY_STRING']
        }
        case e
        when Flapjack::Gateways::JSONAPI::ContactNotFound
          rescue_error.call(404, e, request_info, "could not find contact '#{e.contact_id}'")
        when Flapjack::Gateways::JSONAPI::ContactsNotFound
          rescue_error.call(404, e, request_info, "could not find contacts '" + e.contact_ids.join(', ') + "'")
        when Flapjack::Gateways::JSONAPI::NotificationRuleNotFound
          rescue_error.call(404, e, request_info,"could not find notification rule '#{e.rule_id}'")
        when Flapjack::Gateways::JSONAPI::EntityNotFound
          rescue_error.call(404, e, request_info, "could not find entity '#{e.entity}'")
        when Flapjack::Gateways::JSONAPI::EntityCheckNotFound
          rescue_error.call(404, e, request_info, "could not find entity check '#{e.check}'")
        when Flapjack::Gateways::JSONAPI::ResourceLocked
          rescue_error.call(423, e, request_info, "unable to obtain lock for resource '#{e.resource}'")
        else
          rescue_error.call(500, e, request_info)
        end
      }
      use ::Rack::FiberPool, :size => 25, :rescue_exception => rescue_exception

      use ::Rack::MethodOverride
      use Flapjack::Gateways::JSONAPI::Rack::JsonParamsParser

      class << self
        def start
          @redis = Flapjack::RedisPool.new(:config => @redis_config, :size => 2)

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

      def redis
        self.class.instance_variable_get('@redis')
      end

      def logger
        self.class.instance_variable_get('@logger')
      end

      def base_url
        self.class.instance_variable_get('@base_url')
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

      def is_json_request?
        Flapjack::Gateways::JSONAPI::JSON_REQUEST_MIME_TYPES.include?(request.content_type.split(/\s*[;,]\s*/, 2).first.downcase)
      end

      def is_jsonpatch_request?
        'application/json-patch+json'.eql?(request.content_type.split(/\s*[;,]\s*/, 2).first.downcase)
      end

      register Flapjack::Gateways::JSONAPI::EntityMethods
      register Flapjack::Gateways::JSONAPI::ReportMethods
      register Flapjack::Gateways::JSONAPI::ContactMethods

      # the following should add the cors headers to every request, but is no work
      #register Sinatra::CrossOrigin
      #
      #configure do
      #  enable :cross_origin
      #end
      #set :allow_origin, :any
      #set :allow_methods, [:get, :post, :put, :patch, :delete, :options]

      options '*' do
        cors_headers
        204
      end

      not_found do
        err(404, "not routable")
      end

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

      def location(ids)
        location = "#{base_url}#{request.path_info}#{ids.length == 1 ? '/' + ids.first : '?ids=' + ids.join(',')}"
        headers({'Location' => location})
      end

      private

      def err(status, *msg)
        msg_str = msg.join(", ")
        logger.info "Error: #{msg_str}"
        [status, {}, {:errors => msg}.to_json]
      end
    end

  end

end
