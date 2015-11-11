#!/usr/bin/env ruby

# A HTTP-based API server, which provides queries to determine the status of
# entities and the checks that are reported against them.
#
# There's a matching flapjack-diner gem at https://github.com/flpjck/flapjack-diner
# which consumes data from this API.

require 'time'

require 'sinatra/base'

require 'active_support/inflector'

require 'swagger/blocks'

require 'flapjack'
require 'flapjack/utility'

require 'flapjack/data/acknowledgement'
require 'flapjack/data/check'
require 'flapjack/data/contact'
require 'flapjack/data/medium'
require 'flapjack/data/metrics'
require 'flapjack/data/rule'
require 'flapjack/data/scheduled_maintenance'
require 'flapjack/data/statistic'
require 'flapjack/data/state'
require 'flapjack/data/tag'
require 'flapjack/data/test_notification'
require 'flapjack/data/unscheduled_maintenance'

require 'flapjack/gateways/jsonapi/middleware/array_param_fixer'
require 'flapjack/gateways/jsonapi/middleware/json_params_parser'
require 'flapjack/gateways/jsonapi/middleware/request_timestamp'

%w[headers miscellaneous resources serialiser swagger_docs].each do |helper|
  require "flapjack/gateways/jsonapi/helpers/#{helper}"
end

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      include Flapjack::Utility

      # TODO clean up media type handling for variable character sets
      # append charset in use

      # http://jsonapi.org/extensions/bulk/
      # http://www.iana.org/assignments/media-types/application/vnd.api+json
      JSONAPI_MEDIA_TYPE          = 'application/vnd.api+json'
      JSONAPI_MEDIA_TYPE_BULK     = 'application/vnd.api+json; ext=bulk'

      # # http://tools.ietf.org/html/rfc6902
      # JSON_PATCH_MEDIA_TYPE = 'application/json-patch+json; charset=utf-8'

      RESOURCE_CLASSES = [
        Flapjack::Data::Acknowledgement,
        Flapjack::Data::Check,
        Flapjack::Data::Contact,
        Flapjack::Data::Medium,
        Flapjack::Data::Rule,
        Flapjack::Data::ScheduledMaintenance,
        Flapjack::Data::State,
        Flapjack::Data::Statistic,
        Flapjack::Data::Tag,
        Flapjack::Data::TestNotification,
        Flapjack::Data::UnscheduledMaintenance
      ]

      set :root, File.dirname(__FILE__)

      set :raise_errors, false
      set :show_exceptions, false

      set :protection, :except => :path_traversal

      use Flapjack::Gateways::JSONAPI::Middleware::RequestTimestamp
      use ::Rack::MethodOverride
      use Flapjack::Gateways::JSONAPI::Middleware::ArrayParamFixer
      use Flapjack::Gateways::JSONAPI::Middleware::JsonParamsParser

      class << self

        @@lock = Monitor.new

        def start
          Flapjack.logger.info "starting jsonapi - class"

          if access_log = (@config && @config['access_log'])
            unless File.directory?(File.dirname(access_log))
              raise "Parent directory for log file #{access_log} doesn't exist"
            end

            @access_log = ::Logger.new(@config['access_log'])
            use Rack::CommonLogger, @access_log
          end

        end

        def media_type_produced(options = {})
          unless options[:with_charset].is_a?(TrueClass)
            return 'application/vnd.api+json; supported-ext=bulk'
          end

          media_type = nil
          @@lock.synchronize do
            encoding = Encoding.default_external
            media_type = if encoding.nil?
              'application/vnd.api+json; supported-ext=bulk'
            else
              "application/vnd.api+json; supported-ext=bulk; charset=#{encoding.name.downcase}"
            end
          end
          media_type
        end
      end

      def config
        self.class.instance_variable_get("@config")
      end

      def media_type_produced(options = {})
        self.class.media_type_produced(options)
      end

      before do
        # needs to be done per-thread...
        Flapjack.configure_log('jsonapi', config['logger'])

        # ... as does this
        Zermelo.redis ||= Flapjack.redis

        input = nil
        query_string = (request.query_string.respond_to?(:length) &&
                        request.query_string.length > 0) ? "?#{request.query_string}" : ""
        if Flapjack.logger.debug?
          input = env['rack.input'].read
          Flapjack.logger.debug("#{request.request_method} #{request.path_info}#{query_string} Headers: #{headers.inspect}, Body: #{input}")
        elsif Flapjack.logger.info?
          input = env['rack.input'].read
          input_short = input.gsub(/\n/, '').gsub(/\s+/, ' ')
          Flapjack.logger.info("#{request.request_method} #{request.path_info}#{query_string} #{input_short[0..80]}")
        end
        env['rack.input'].rewind unless input.nil?
      end

      after do
        return if response.status == 500

        query_string = (request.query_string.respond_to?(:length) &&
                        request.query_string.length > 0) ? "?#{request.query_string}" : ""
        if Flapjack.logger.debug?
          body_debug = case
          when response.body.respond_to?(:each)
            response.body.each_with_index {|r, i| "body[#{i}]: #{r}"}.join(', ')
          else
            response.body.to_s
          end
          headers_debug = response.headers.to_s
          Flapjack.logger.debug("Returning #{response.status} for #{request.request_method} " +
            "#{request.path_info}#{query_string}, headers: #{headers_debug}, body: #{body_debug}")
        elsif Flapjack.logger.info?
          Flapjack.logger.info("Returning #{response.status} for #{request.request_method} " +
            "#{request.path_info}#{query_string}")
        end
      end

      options '*' do
        cors_headers
        204
      end

      # FIXME enforce that Accept header must allow defined return type for the method

      # The following catch-all routes act as impromptu filters for their method types
      get '*' do
        cors_headers
        content_type media_type_produced(:with_charset => true)
        pass
      end

      # bare 'params' may have splat/captures for regex route, see
      # https://github.com/sinatra/sinatra/issues/453
      post '*' do
        halt(405) unless request.params.empty? || is_jsonapi_request?
        cors_headers
        content_type media_type_produced(:with_charset => true)
        pass
      end

      patch '*' do
        halt(405) unless request.params.empty? || is_jsonapi_request?
        cors_headers
        content_type media_type_produced(:with_charset => true)
        pass
      end

      delete '*' do
        cors_headers
        pass
      end

      include Swagger::Blocks
      include Flapjack::Gateways::JSONAPI::Helpers::SwaggerDocs

      # hacky, but trying to avoid too much boilerplate -- association paths
      # must be before resource ones to avoid greedy path captures
      %w[metrics association_post resource_post association_get resource_get
         association_patch resource_patch association_delete
         resource_delete].each do |method|

        require "flapjack/gateways/jsonapi/methods/#{method}"
        eval "register Flapjack::Gateways::JSONAPI::Methods::#{method.camelize}"
      end

      Flapjack::Gateways::JSONAPI::RESOURCE_CLASSES.each do |resource_class|
        endpoint = resource_class.short_model_name.plural
        swagger_wrappers(endpoint, resource_class)
      end

      SWAGGERED_CLASSES = [self] + Flapjack::Gateways::JSONAPI::RESOURCE_CLASSES +
        [Flapjack::Data::Metrics]

      get '/doc' do
        Flapjack.dump_json(Swagger::Blocks.build_root_json(SWAGGERED_CLASSES))
      end

      # error Zermelo::LockNotAcquired do
      #   # TODO
      # end

      error Zermelo::Records::Errors::RecordInvalid do
        e = env['sinatra.error']
        err(403, *e.record.errors.full_messages)
      end

      error Zermelo::Records::Errors::RecordNotSaved do
        e = env['sinatra.error']
        err(403, *e.record.errors.full_messages)
      end

      error Zermelo::Records::Errors::RecordNotFound do
        e = env['sinatra.error']
        type = e.klass.name.split('::').last
        err(404, "could not find #{type} record, id: '#{e.id}'")
      end

      error Zermelo::Records::Errors::RecordsNotFound do
        e = env['sinatra.error']
        type = e.klass.name.split('::').last
        err_ids = e.ids.join("', '")
        err(404, "could not find #{type} records, ids: '#{err_ids}'")
      end

      error do
        e = env['sinatra.error']
        # trace = e.backtrace.join("\n")
        # puts trace
        err(response.status, "#{e.class} - #{e.message}")
      end

    end
  end
end
