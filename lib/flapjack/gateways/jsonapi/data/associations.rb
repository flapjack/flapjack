#!/usr/bin/env ruby

require 'active_support/concern'
require 'active_support/inflector'
require 'active_support/core_ext/hash/slice'

require 'sinatra/base'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Data
        module Associations

          extend ActiveSupport::Concern

          module ClassMethods

            def jsonapi_locks(http_method)
              http_m = http_method.to_s.downcase
              access_types = 'get'.eql?(http_m) ? [:read_write, :read_only] : [:read_write]

              access_types, extra_locks = case http_m
              when 'get'
                [
                  [:read_write, :read_only],
                  self.jsonapi_extra_locks[http_m.to_sym] | (
                    (self.jsonapi_linked_methods[:singular].values.reduce(:|) || []) +
                    (self.jsonapi_linked_methods[:multiple].values.reduce(:|) || [])
                  )
                ]
              else
                [
                  [:read_write],
                  self.jsonapi_extra_locks[http_m.to_sym]
                ]
              end

              data = jsonapi_association_data.slice(*access_types)

              access_types.each_with_object(Set.new) {|access_type, memo|
                [:singular, :multiple].each do |num_type|
                  data[access_type][num_type].values.each do |lv|
                    memo.add(lv[:data])
                    memo.merge(lv[:related])
                  end
                end
              }.merge(extra_locks)
            end

            def jsonapi_association_links(*access_types)
              data = jsonapi_association_data.slice(*access_types)

              access_types.each_with_object({}) do |access_type, memo|
                [:singular, :multiple].each do |num_type|
                  # merge access types under a single num_type
                  memo[num_type] ||= {}
                  memo[num_type].update(data[access_type][num_type])
                  if :read_only.eql?(access_type)
                    extra_links = self.jsonapi_linked_methods[num_type].each_with_object({}) do |(name, klasses), memo|
                      data_klass = klasses.first
                      related_klasses = data_klass.nil? ? [] : (klasses - [data_klass])
                      memo[name] = {
                        :data => data_klass,
                        :related => related_klasses,
                        :type => data_klass.name.demodulize,
                        :name => name,
                        :is_association => false
                      }
                    end
                    memo[num_type].update(extra_links)
                  end
                end
              end
            end

            private

            def jsonapi_association_data
              return @jsonapi_association_data unless @jsonapi_association_data.nil?

              @jsonapi_association_data = {
                :read_write => {:singular => {}, :multiple => {}},
                :read_only  => {:singular => {}, :multiple => {}}
              }

              assocs = self.respond_to?(:jsonapi_associations) ?
                self.jsonapi_associations : {}

              return @jsonapi_association_data if assocs.empty?

              # SMELL mucking about with a zermelo protected method...
              self.with_association_data do |assoc_data|
                assoc_data.each_pair do |name, data|
                  [:read_write, :read_only].each do |access|
                    [:singular, :multiple].each do |num_type|
                      next unless (((assocs[access] || {})[num_type]) || []).include?(name)
                      @jsonapi_association_data[access][num_type][name] = {
                        :data => data.data_klass,
                        :related => data.related_klasses,
                        :type => data.data_klass.name.demodulize,
                        :name => name,
                        :is_association => true
                      }
                    end
                  end
                end

                @jsonapi_association_data
              end
            end
          end
        end
      end
    end
  end
end
