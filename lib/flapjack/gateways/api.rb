#!/usr/bin/env ruby

# A HTTP-based API server, which provides queries to determine the status of
# entities and the checks that are reported against them.
#
# There's a matching flapjack-diner gem at https://github.com/flpjck/flapjack-diner
# which consumes data from this API.

require 'time'

require 'sinatra/base'

require 'flapjack/redis_proxy'

require 'flapjack/gateways/api/rack/json_params_parser'
require 'flapjack/gateways/api/contact_methods'
require 'flapjack/gateways/api/entity_methods'

module Flapjack

  module Gateways

    class API < Sinatra::Base

      include Flapjack::Utility

      set :raise_errors, true
      set :show_exceptions, false

      use Rack::MethodOverride
      use Rack::JsonParamsParser

      class << self
        def start
          @logger.info "starting api - class"

          if accesslog = (@config && @config['access_log'])
            if not File.directory?(File.dirname(accesslog))
              puts "Parent directory for log file #{accesslog} doesn't exist"
              puts "Exiting!"
              exit
            end

            use Rack::CommonLogger, ::Logger.new(@config['access_log'])
          end
        end
      end

      ['logger', 'config'].each do |class_inst_var|
        define_method(class_inst_var.to_sym) do
          self.class.instance_variable_get("@#{class_inst_var}")
        end
      end

      before do
        input = env['rack.input'].read
        input_short = input.gsub(/\n/, '').gsub(/\s+/, ' ')
        logger.info("#{request.request_method} #{request.path_info}#{request.query_string} #{input_short[0..80]}")
        logger.debug("#{request.request_method} #{request.path_info}#{request.query_string} #{input}")
        env['rack.input'].rewind
      end

      after do
        logger.debug("Returning #{response.status} for #{request.request_method} #{request.path_info}#{request.query_string}")
      end

      register Flapjack::Gateways::API::EntityMethods

      register Flapjack::Gateways::API::ContactMethods

      not_found do
        logger.debug("in not_found :-(")
        err(404, "not routable")
      end

      error Flapjack::Gateways::API::ContactNotFound do
        e = env['sinatra.error']
        err(403, "could not find contact '#{e.contact_id}'")
      end

      error Flapjack::Gateways::API::NotificationuleNotFound do
        e = env['sinatra.error']
        err(403, "could not find notification rule '#{e.rule_id}'")
      end

      error Flapjack::Gateways::API::EntityNotFound do
        e = env['sinatra.error']
        err(403, "could not find entity '#{e.entity}'")
      end

      error Flapjack::Gateways::API::EntityCheckNotFound do
        e = env['sinatra.error']
        err(403, "could not find entity check '#{e.check}'")
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
