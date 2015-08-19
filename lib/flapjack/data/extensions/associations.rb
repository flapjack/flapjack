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
            locks ||= []

            if :delete.eql?(http_method)
              # all associations, not just the ones exposed via JSONAPI
              self.send(:with_association_data) do |assoc_data|
                assoc_data.each_pair do |name, data|
                  locks |= [data.data_klass] + data.related_klasses
                end
              end

              locks |= jsonapi_associations.values.select {|a|
                !a.type.nil?
              }.map(&:lock_klasses).reduce([], :|)
            end

            if locks.empty?
              self.lock(&block)
            else
              locks.sort_by!(&:name)
              self.lock(*locks, &block)
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