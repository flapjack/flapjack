#!/usr/bin/env ruby

require 'sinatra/base'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Data
        class JoinDescriptor
          attr_reader :post, :get, :patch, :delete, :number, :link, :includable, :type
          attr_accessor :association_data

          def initialize(opts = {})
            %w{post get patch delete number link includable type lock_klasses}.each do |a|
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
            @association_data.nil? ? @type : data_klass.short_model_name.singular
          end
        end
      end
    end
  end
end