#!/usr/bin/env ruby

require 'net/http'
require 'yajl/json_gem'

module Flapjack
  module Persistence
    class Couch

      attr_accessor :config

      def initialize(options={})
        @options = options
        @config = OpenStruct.new(options)
        @log = @config.log

        self.class.setup(@options)
      end

      def any_parents_failed?(result)
        ids = self.class.get(result.result.check_id)["parent_checks"] || []
        ids.find_all { |id| self.class.get(id)["status"] != "0" }.size > 0
      end

      class << self
        attr_accessor :host, :port
        def setup(options={})
          @host = options[:host]
          @port = options[:port]
          @database = options[:database]
        end

        def get(id)
          uri = "/#{@database}/#{id}"
          req = ::Net::HTTP::Get.new(uri)
          request(req)
        end

        def post(options={})
          document = options[:document]
          uri = "/#{@database}/"

          req = ::Net::HTTP::Post.new(uri)
          req["content-type"] = "application/json"
          req.body = document.to_json

          request(req) 
        end

        def put(options={})
          document = options[:document]
          uri = "/#{@database}/#{options[:document]["id"]}"

          req = ::Net::HTTP::Put.new(uri)
          req["content-type"] = "application/json"
          req.body = document.to_json

          request(req) 
        end

        def request(request)
          response = Net::HTTP.start(@host, @port) {|http| http.request(request)}
         
          unless response.kind_of?(Net::HTTPSuccess)
            handle_error(request, response)
          end

          @parser = Yajl::Parser.new
          hash = @parser.parse(response.body)
        end

        def handle_error(req, res)
          e = RuntimeError.new("#{res.code}:#{res.message}\nMETHOD:#{req.method}\nURI:#{req.path}\n#{res.body}")
          raise e
        end
      end
    end # class Couch
  end # module Persistence
end # module Flapjack

