#!/usr/bin/env ruby

require 'sinatra/base'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Data
        class JoinDescriptor
          attr_reader :writable, :number, :link, :include, :type
          attr_accessor :association_data

          def initialize(opts = {})
            %w{writable number link include type lock_klasses}.each do |a|
              instance_variable_set("@#{a}", opts[a.to_sym])
            end
            @lock_klasses ||= []
          end

          def lock_klasses
            @lock_klasses | (@association_data.nil? ? [] :
                             ([@association_data.data_klass] |
                              (@association_data.related_klasses || [])))
          end

          def data_klass
            @association_data.nil? ? nil : @association_data.data_klass
          end

          def type
            @association_data.nil? ? @type : data_klass.jsonapi_type
          end
        end
      end
    end
  end
end