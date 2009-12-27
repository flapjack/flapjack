#!/usr/bin/env ruby

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
            uri = "/#{@database}/#{(options[:document]["id"] || options[:document]["_id"])}"
  
            req = ::Net::HTTP::Put.new(uri)
            req["content-type"] = "application/json"
            req.body = document.to_json
  
            request(req) 
          end

          def delete(options={})
            document = options[:document]

            uri = "/#{@database}/#{(options[:document]["id"] || options[:document]["_id"])}"
  
            req = ::Net::HTTP::Put.new(uri)
            req["content-type"] = "application/json"
            req.body = document.to_json

            request(req)
          end
  
          def request(request)
            response = Net::HTTP.start(@host, @port) {|http| http.request(request)}
           
            @parser = Yajl::Parser.new
            hash = @parser.parse(response.body)
          end
        end
      end
    end # class Couch
  end # module Persistence
end # module Flapjack

