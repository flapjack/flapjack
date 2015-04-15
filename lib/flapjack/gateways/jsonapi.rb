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

require 'flapjack/data/check'
require 'flapjack/data/contact'
require 'flapjack/data/medium'
require 'flapjack/data/rule'
require 'flapjack/data/scheduled_maintenance'
require 'flapjack/data/tag'
require 'flapjack/data/unscheduled_maintenance'

require 'flapjack/gateways/jsonapi/rack/array_param_fixer'
require 'flapjack/gateways/jsonapi/rack/json_params_parser'

%w[headers miscellaneous resources resource_links
   swagger_docs swagger_links_docs].each do |helper|
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
      JSONAPI_MEDIA_TYPE_PRODUCED = 'application/vnd.api+json; supported-ext=bulk; charset=utf-8'

      # # http://tools.ietf.org/html/rfc6902
      # JSON_PATCH_MEDIA_TYPE = 'application/json-patch+json; charset=utf-8'

      RESOURCE_CLASSES = [
        Flapjack::Data::Check,
        Flapjack::Data::Contact,
        Flapjack::Data::Medium,
        Flapjack::Data::Rule,
        Flapjack::Data::ScheduledMaintenance,
        Flapjack::Data::Tag,
        Flapjack::Data::UnscheduledMaintenance
      ]

      set :raise_errors, true
      set :show_exceptions, false

      set :protection, :except => :path_traversal

      # use ::Rack::Lint
      use ::Rack::MethodOverride
      use Flapjack::Gateways::JSONAPI::Rack::ArrayParamFixer
      use Flapjack::Gateways::JSONAPI::Rack::JsonParamsParser

      class << self
        def start
          Flapjack.logger.info "starting jsonapi - class"
        end
      end

      def config
        self.class.instance_variable_get("@config")
      end

      before do
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
        content_type JSONAPI_MEDIA_TYPE_PRODUCED
        cors_headers
        pass
      end

      # bare 'params' may have splat/captures for regex route, see
      # https://github.com/sinatra/sinatra/issues/453
      post '*' do
        halt(405) unless request.params.empty? || is_jsonapi_request?
        content_type JSONAPI_MEDIA_TYPE_PRODUCED
        cors_headers
        pass
      end

      # put '*' do
      #   halt(405) unless request.params.empty? || is_jsonapi_request?
      #   content_type JSONAPI_MEDIA_TYPE_PRODUCED
      #   cors_headers
      #   pass
      # end

      patch '*' do
        halt(405) unless request.params.empty? || is_jsonapi_request?
        content_type JSONAPI_MEDIA_TYPE_PRODUCED
        cors_headers
        pass
      end

      delete '*' do
        cors_headers
        pass
      end

      include Swagger::Blocks
      include Flapjack::Gateways::JSONAPI::Helpers::SwaggerDocs
      include Flapjack::Gateways::JSONAPI::Helpers::SwaggerLinksDocs

      swagger_root do
        key :swagger, '2.0'
        info do
          key :version, '2.0.0'
          key :title, 'Flapjack API'
          key :description, ''
          contact do
            key :name, ''
          end
          license do
            key :name, 'MIT'
          end
        end
        key :host, 'localhost'
        key :basePath, '/doc'
        key :schemes, ['http']
        key :consumes, [JSONAPI_MEDIA_TYPE]
        key :produces, [JSONAPI_MEDIA_TYPE]
      end

      # hacky, but trying to avoid too much boilerplate -- links paths
      # must be before regular ones to avoid greedy path captures
      %w[metrics reports test_notifications resource_links resources].each do |method|

        require "flapjack/gateways/jsonapi/methods/#{method}"
        eval "register Flapjack::Gateways::JSONAPI::Methods::#{method.camelize}"
      end

      swagger_schema :jsonapi_Reference do
        key :required, [:type, :id]
        property :type do
          key :type, :string
          key :enum, Flapjack::Gateways::JSONAPI::RESOURCE_CLASSES.map(&:jsonapi_type)
        end
        property :id do
          key :type, :string
          key :format, :uuid
        end
      end

      swagger_schema :jsonapi_Links do
        key :required, [:self]
        property :self do
          key :type, :string
          key :format, :url
        end
        property :first do
          key :type, :string
          key :format, :url
        end
        property :last do
          key :type, :string
          key :format, :url
        end
        property :next do
          key :type, :string
          key :format, :url
        end
        property :prev do
          key :type, :string
          key :format, :url
        end
      end

      swagger_schema :jsonapi_Pagination do
        key :required, [:page, :per_page, :total_pages, :total_count]
        property :page do
          key :type, :integer
          key :format, :int64
        end
        property :per_page do
          key :type, :integer
          key :format, :int64
        end
        property :total_pages do
          key :type, :integer
          key :format, :int64
        end
        property :total_count do
          key :type, :integer
          key :format, :int64
        end
      end

      swagger_schema :jsonapi_Meta do
        property :pagination do
          key :"$ref", :jsonapi_Pagination
        end
      end

      Flapjack::Gateways::JSONAPI::RESOURCE_CLASSES.each do |resource_class|
        endpoint = resource_class.jsonapi_type.pluralize.downcase
        swagger_wrappers(endpoint, resource_class)
      end

      SWAGGERED_CLASSES = [self] + Flapjack::Gateways::JSONAPI::RESOURCE_CLASSES

      get '/doc' do
        Flapjack.dump_json(Swagger::Blocks.build_root_json(SWAGGERED_CLASSES))
      end

      # error Zermelo::LockNotAcquired do
      #   # TODO
      # end

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
