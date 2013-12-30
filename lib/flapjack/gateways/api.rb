#!/usr/bin/env ruby

# A HTTP-based API server, which provides queries to determine the status of
# entities and the checks that are reported against them.
#
# There's a matching flapjack-diner gem at https://github.com/flpjck/flapjack-diner
# which consumes data from this API.

require 'time'

require 'rack/fiber_pool'
require 'sinatra/base'
require 'sinatra/cross_origin'

require 'flapjack/rack_logger'
require 'flapjack/redis_pool'

require 'flapjack/gateways/api/rack/json_params_parser'

require 'flapjack/gateways/api/contact_methods'
require 'flapjack/gateways/api/entity_methods'

module Flapjack

  module Gateways

    class API < Sinatra::Base

      include Flapjack::Utility

      class ContactNotFound < RuntimeError
        attr_reader :contact_id
        def initialize(contact_id)
          @contact_id = contact_id
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
        elsif logger.info?
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
        when Flapjack::Gateways::API::ContactNotFound
          rescue_error.call(404, e, request_info, "could not find contact '#{e.contact_id}'")
        when Flapjack::Gateways::API::NotificationRuleNotFound
          rescue_error.call(404, e, request_info,"could not find notification rule '#{e.rule_id}'")
        when Flapjack::Gateways::API::EntityNotFound
          rescue_error.call(404, e, request_info, "could not find entity '#{e.entity}'")
        when Flapjack::Gateways::API::EntityCheckNotFound
          rescue_error.call(404, e, request_info, "could not find entity check '#{e.check}'")
        when Flapjack::Gateways::API::ResourceLocked
          rescue_error.call(423, e, request_info, "unable to obtain lock for resource '#{e.resource}'")
        else
          rescue_error.call(500, e, request_info)
        end
      }
      use Rack::FiberPool, :size => 25, :rescue_exception => rescue_exception

      use Rack::MethodOverride
      use Rack::JsonParamsParser

      class << self
        def start
          @redis = Flapjack::RedisPool.new(:config => @redis_config, :size => 2)

          @logger.info "starting api - class"

          if @config && @config['access_log']
            access_logger = Flapjack::AsyncLogger.new(@config['access_log'])
            use Flapjack::CommonLogger, access_logger
          end
        end
      end

      def redis
        self.class.instance_variable_get('@redis')
      end

      def logger
        self.class.instance_variable_get('@logger')
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
          logger.debug("Returning #{response.status} for #{request.request_method} " +
            "#{request.path_info}#{query_string}, body: #{response.body.join(', ')}")
        elsif logger.info?
          logger.info("Returning #{response.status} for #{request.request_method} " +
            "#{request.path_info}#{query_string}")
        end
      end

      register Flapjack::Gateways::API::EntityMethods

      register Flapjack::Gateways::API::ContactMethods

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

      private

      def err(status, *msg)
        msg_str = msg.join(", ")
        logger.info "Error: #{msg_str}"
        [status, {}, {:errors => msg}.to_json]
      end
    end

  end

end
