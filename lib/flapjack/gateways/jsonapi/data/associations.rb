#!/usr/bin/env ruby

require 'active_support/concern'
require 'active_support/inflector'

require 'sinatra/base'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Data
        module Associations

          extend ActiveSupport::Concern

          module ClassMethods

            def association_klasses
              singular = self.respond_to?(:jsonapi_singular_associations) ?
                self.jsonapi_singular_associations : []
              multiple = self.respond_to?(:jsonapi_multiple_associations) ?
                self.jsonapi_multiple_associations : []

              singular_aliases, singular_names = singular.partition {|s| s.is_a?(Hash)}
              multiple_aliases, multiple_names = multiple.partition {|m| m.is_a?(Hash)}

              singular_links = {}
              multiple_links = {}

              # SMELL mucking about with a zermelo protected method...
              self.with_association_data do |assoc_data|
                assoc_data.each_pair do |name, data|
                  assoc_attrs = {
                      :data => data.data_klass, :related => data.related_klasses,
                      :type => data.data_klass.name.demodulize,
                      :name => name
                    }
                  if sa = singular_aliases.detect {|a| a.has_key?(name) }
                    singular_links[sa[name]] = assoc_attrs
                  elsif singular_names.include?(name)
                    singular_links[name] = assoc_attrs
                  elsif ma = multiple_aliases.detect {|a| a.has_key?(name) }
                    multiple_links[ma[name]] = assoc_attrs
                  elsif multiple_names.include?(name)
                    multiple_links[name] = assoc_attrs
                  end
                end
              end

              [singular_links, multiple_links]
            end

          end

        end
      end
    end
  end
end
