#!/usr/bin/env ruby

# A HTTP-based API server, which provides queries to determine the status of
# entities and the checks that are reported against them.
#
# There's a matching flapjack-diner gem at https://github.com/flpjck/flapjack-diner
# which consumes data from this API.

require 'time'

require 'sinatra/base'

require 'flapjack/gateways/jsonapi/rack/json_params_parser'

require 'flapjack/gateways/jsonapi/contact_methods'
require 'flapjack/gateways/jsonapi/entity_methods'

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      include Flapjack::Utility

      JSON_REQUEST_MIME_TYPES = ['application/vnd.api+json', 'application/json']

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

      class CheckNotFound < RuntimeError
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
          logger.debug("Returning #{response.status} for #{request.request_method} " +
            "#{request.path_info}#{query_string}, body: #{response.body.join(', ')}")
        elsif logger.info?
          logger.info("Returning #{response.status} for #{request.request_method} " +
            "#{request.path_info}#{query_string}")
        end
      end

      register Flapjack::Gateways::JSONAPI::EntityMethods

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
        location = "#{config['base_url']}#{request.path_info}#{ids.length == 1 ? '/' + ids.first : '?ids=' + ids.join(',')}"
        headers({'Location' => location})
      end

      not_found do
        err(404, "not routable")
      end

      error Flapjack::Gateways::JSONAPI::ContactNotFound do
        e = env['sinatra.error']
        err(404, "could not find contact '#{e.contact_id}'")
      end

      error Flapjack::Gateways::JSONAPI::NotificationRuleNotFound do
        e = env['sinatra.error']
        err(404, "could not find notification rule '#{e.rule_id}'")
      end

      error Flapjack::Gateways::JSONAPI::EntityNotFound do
        e = env['sinatra.error']
        err(404, "could not find entity '#{e.entity}'")
      end

      error Flapjack::Gateways::JSONAPI::CheckNotFound do
        e = env['sinatra.error']
        err(404, "could not find entity check '#{e.check}'")
      end

      error do
        e = env['sinatra.error']
        err(response.status, "#{e.class} - #{e.message}")
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
