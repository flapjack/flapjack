#!/usr/bin/env ruby

require 'sinatra/base'

# klass and type are set for those relationships that call methods rather
# than regular Zermelo associations. Maybe this should be a separate descriptor type?

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Data
        class JoinDescriptor
          attr_reader :post, :get, :patch, :delete, :number, :link, :includable, :klass, :descriptions
          attr_accessor :association_data

          def initialize(opts = {})
            @association_data = nil
            %w{post get patch delete number link includable type klass callback_classes descriptions}.each do |a|
              instance_variable_set("@#{a}", opts[a.to_sym])
            end
            @callback_classes ||= []
          end

          def lock_klasses
            if @association_data.nil?
              [@klass] | @callback_classes
            else
              [@association_data.data_klass] |
                @association_data.related_klasses | @callback_classes
            end
          end

          def data_klass
            @association_data.nil? ? @klass : @association_data.data_klass
          end

          def type
            @association_data.nil? ? @type : data_klass.short_model_name.singular
          end
        end
      end
    end
  end
end