#!/usr/bin/env ruby

require 'sinatra/base'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Data
        class MethodDescriptor
          attr_reader :attributes, :lock_klasses, :descriptions

          def initialize(opts = {})
            %w{attributes lock_klasses descriptions}.each do |a|
              instance_variable_set("@#{a}", opts[a.to_sym])
            end
          end
        end
      end
    end
  end
end