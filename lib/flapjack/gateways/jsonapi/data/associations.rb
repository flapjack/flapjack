#!/usr/bin/env ruby

require 'active_support/concern'
require 'active_support/inflector'
require 'active_support/core_ext/hash/slice'

require 'sinatra/base'

require 'flapjack/gateways/jsonapi/data/join_descriptor'
require 'flapjack/gateways/jsonapi/data/method_descriptor'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Data
        module Associations

          extend ActiveSupport::Concern

          module ClassMethods

            def jsonapi_lock_method(http_method, &block)
              locks = case http_method.to_sym
              when :get
                jsonapi_association_links.values.map(&:lock_klasses).reduce(:|) || []
              else
                jsonapi_association_links.values.reject {|jal| !jal.writable }.map(&:lock_klasses).reduce(:|) || []
              end
              locks |= ((jsonapi_methods[http_method] || {}).lock_klasses || [])
              return yield if locks.empty?
              lock(*locks) do
                yield
              end
            end

            def jsonapi_association_links
              return @jsonapi_association_links unless @jsonapi_association_links.nil?

              # SMELL mucking about with a zermelo protected method...
              self.send(:with_association_data) do |assoc_data|
                assoc_data.each_pair do |name, data|
                  ja = jsonapi_associations[name.to_sym]
                  next if ja.nil?
                  ja.association_data = data
                end
              end

              @jsonapi_association_links = @jsonapi_associations || {}
              @jsonapi_association_links
            end
          end
        end
      end
    end
  end
end
