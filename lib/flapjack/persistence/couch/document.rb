#!/usr/bin/env ruby

module Flapjack
  module Persistence
    class Couch
      class Document
        def initialize(options={})
          @options = options
          @config = OpenStruct.new(options)
          @log = @config.log

          @table = @options.dup
        end

        def save
          document = @table
          if @persisted
            response = Flapjack::Persistence::Couch.put(:document => document)
          else
            response = Flapjack::Persistence::Couch.post(:document => document)
          end

          @table["id"]  = response["id"]
          @table["_rev"] = response["rev"]
          @persisted = true

          response["ok"]
        end

        def status=(value)
          @table["status"] = value
        end

        def id
          @table["id"]
        end
      end # class Document
    end # class Couch
  end # module Persistence
end # module Flapjack
