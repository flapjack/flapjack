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

require 'flapjack/gateways/api/rack/json_params_parser'

require 'flapjack/gateways/api/contact_methods'
require 'flapjack/gateways/api/entity_methods'

module Flapjack

  module Gateways

    class API < Sinatra::Base

      include Flapjack::Utility

      set :show_exceptions, false

      rescue_exception = Proc.new { |env, exception|

        error = proc {|status, exception, *msg|
          if !msg || msg.empty?
            trace = exception.backtrace.join("\n")
            msg = "#{exception.class} - #{exception.message}"
            msg_str = "#{msg}\n#{trace}"
          else
            msg_str = msg.join(", ")
          end
          logger = Flapjack::Gateways::API.instance_variable_get('@logger')
          case
          when status < 500
            logger.warn "Error: #{msg_str}"
          else
            logger.error "Error: #{msg_str}"
          end
          [status, {}, {:errors => msg}.to_json]
        }

        e = env['sinatra.error']

        case exception
        when Flapjack::Gateways::API::ContactNotFound
          error.call(403, e, "could not find contact '#{e.contact_id}'")
        when Flapjack::Gateways::API::NotificationRuleNotFound
          error.call(403, e, "could not find notification rule '#{e.rule_id}'")
        when Flapjack::Gateways::API::EntityNotFound
          error.call(403, e, "could not find entity '#{e.entity}'")
        when Flapjack::Gateways::API::EntityCheckNotFound
          error.call(403, e, "could not find entity check '#{e.check}'")
        else
          error.call(500, exception)
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
        if logger.debug?
          input = env['rack.input'].read
          logger.debug("#{request.request_method} #{request.path_info}#{request.query_string} #{input}")
        elsif logger.info?
          input = env['rack.input'].read
          input_short = input.gsub(/\n/, '').gsub(/\s+/, ' ')
          logger.info("#{request.request_method} #{request.path_info}#{request.query_string} #{input_short[0..80]}")
        end
        env['rack.input'].rewind unless input.nil?
      end

      after do
        if logger.debug?
          logger.debug("Returning #{response.status} for #{request.request_method} #{request.path_info}#{request.query_string}, body: [#{response.body.join(', ')}]")
        elsif logger.info?
          logger.info("Returning #{response.status} for #{request.request_method} #{request.path_info}#{request.query_string}")
        end
      end

      register Flapjack::Gateways::API::EntityMethods

      register Flapjack::Gateways::API::ContactMethods

      not_found do
        err(404, "not routable")
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
