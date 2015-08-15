#!/usr/bin/env ruby

require 'active_support/concern'
require 'active_support/inflector'
require 'active_support/core_ext/hash/slice'

require 'sinatra/base'

require 'flapjack/gateways/jsonapi/data/join_descriptor'
require 'flapjack/gateways/jsonapi/data/method_descriptor'

module Flapjack
  module Data
    module Extensions
      module Associations

        extend ActiveSupport::Concern

        module ClassMethods

          def jsonapi_lock_method(http_method, locks = nil, &block)
            method_defs = if self.respond_to?(:jsonapi_methods)
              self.jsonapi_methods
            else
              {}
            end

            method_def = method_defs[http_method]

            locks ||= []
            unless method_def.nil?
              l = (method_def.lock_klasses || [])
              case http_method
              when :delete
               l |= (jsonapi_associations.values.map(&:lock_klasses).reduce(:|) || [])
              else
                jsonapi_associations.each_pair do |n, jal|
                  next unless jal.send(http_method.to_sym).is_a?(TrueClass)
                  l |= (jal.lock_klasses || [])
                end
              end
              locks |= l
            end

            if locks.empty?
              self.lock { yield }
            else
              locks.sort_by!(&:name)
              self.lock(*locks) { yield }
            end
          end

          def populate_association_data(jsonapi_assoc)
            # SMELL mucking about with a zermelo protected method...
            self.send(:with_association_data) do |assoc_data|
              assoc_data.each_pair do |name, data|
                ja = jsonapi_assoc[name.to_sym]
                next if ja.nil?
                ja.association_data = data
              end
            end
          end
        end
      end
    end
  end
end