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
        
        Flapjack::Persistence::Couch::Connection.setup(@options)
      end

      def any_parents_failed?(result)
        ids = self.class.get(result.result.check_id)["parent_checks"] || []
        ids.find_all { |id| self.class.get(id)["status"] != "0" }.size > 0
      end

      def save(result)
        response = self.class.get(result.result.check_id)
        check = Flapjack::Persistence::Couch::Document.new(response)
        check.status = result.result.retval
        check.save
      end

      def create_event(result)
        event = result.result.to_h.reject {|key, value| key == :check_id}
        event.merge!(:when => Time.now.strftime("%Y-%m-%d %H:%M:%S%z"))

        check = Flapjack::Persistence::Couch::Document.get(result.result.check_id)
        check['events'] ||= []
        check['events'] << event

        check.save
      end

      def get_check(id)
        Flapjack::Persistence::Couch::Document.get(id)
      end


      def save_check(opts={})
        if response = Flapjack::Persistence::Couch::Connection.get(opts[:id])
          opts[:_type] = "check"
          check = Flapjack::Persistence::Couch::Document.new(response)
          check.update_attributes(opts)
        else
          check = Flapjack::Persistence::Couch::Document.new(opts)
          check.save
        end
      end

    end # class Couch
  end # module Persistence
end # module Flapjack

module Flapjack
  module Persistence
    class Couch
      class Connection
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
            begin 
              request(req)
            rescue RuntimeError
              nil
            end
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
            uri = "/#{@database}/#{(options[:document]["id"] || options[:document]["_id"])}"
  
            req = ::Net::HTTP::Put.new(uri)
            req["content-type"] = "application/json"
            req.body = document.to_json
  
            request(req) 
          end
  
          def request(request)
            response = Net::HTTP.start(@host, @port) {|http| http.request(request)}
           
            if response.kind_of?(Net::HTTPSuccess)
              @parser = Yajl::Parser.new
              hash = @parser.parse(response.body)
            else 
              nil
            end
          end
        end
      end
    end # class Couch
  end # module Persistence
end # module Flapjack

