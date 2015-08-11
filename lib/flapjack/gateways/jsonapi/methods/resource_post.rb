#!/usr/bin/env ruby

require 'sinatra/base'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module ResourcePost

          module Helpers
            def id_from_data(id_field, data)
              case id_field
              when :id
                data['id']
              else
                if data.has_key?('attributes')
                  data['attributes'][id_field]
                else
                  nil
                end
              end
            end
          end

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Resources
            app.helpers Flapjack::Gateways::JSONAPI::Methods::ResourcePost::Helpers

            Flapjack::Gateways::JSONAPI::RESOURCE_CLASSES.each do |resource_class|

              method_defs = if resource_class.respond_to?(:jsonapi_methods)
                resource_class.jsonapi_methods
              else
                {}
              end

              method_def = method_defs[:post]

              unless method_def.nil?
                resource = resource_class.short_model_name.plural

                jsonapi_links = if resource_class.respond_to?(:jsonapi_associations)
                  resource_class.jsonapi_associations || {}
                else
                  {}
                end

                singular_links = jsonapi_links.select {|n, jd|
                  jd.send(:post).is_a?(TrueClass) && :singular.eql?(jd.number)
                }

                multiple_links = jsonapi_links.select {|n, jd|
                  jd.send(:post).is_a?(TrueClass) && :multiple.eql?(jd.number)
                }

                app.class_eval do
                  single = resource_class.short_model_name.singular

                  model_type = resource_class.short_model_name.name

                  model_type_data = "jsonapi_data_#{model_type}".to_sym
                  model_type_create_data = "jsonapi_data_#{model_type}Create".to_sym

                  # TODO how to include plural for same route?

                  swagger_path "/#{resource}" do
                    operation :post do
                      key :description, "Create a #{single}"
                      key :operationId, "create_#{single}"
                      key :consumes, [JSONAPI_MEDIA_TYPE]
                      key :produces, [Flapjack::Gateways::JSONAPI.media_type_produced]
                      parameter do
                        key :name, :body
                        key :in, :body
                        key :description, "#{single} to create"
                        key :required, true
                        schema do
                          key :"$ref", model_type_create_data
                        end
                      end
                      response 200 do
                        key :description, "#{single} creation response"
                        schema do
                          key :'$ref', model_type_data
                        end
                      end
                      # response :default do
                      #   key :description, 'unexpected error'
                      #   schema do
                      #     key :'$ref', :ErrorModel
                      #   end
                      # end
                    end
                  end

                end

                app.post "/#{resource}" do
                  status 201

                  resources_data, unwrap = wrapped_params

                  attributes = method_def.attributes || []

                  validate_data(resources_data, :attributes => attributes,
                    :singular_links => singular_links,
                    :multiple_links => multiple_links,
                    :klass => resource_class)

                  resources = nil

                  id_field = resource_class.respond_to?(:jsonapi_id) ?
                               resource_class.jsonapi_id.to_sym : :id

                  data_ids = resources_data.each_with_object([]) do |d, memo|
                    d_id = id_from_data(id_field, d)
                    memo << d_id.to_s unless d_id.nil?
                  end

                  attribute_types = resource_class.attribute_types

                  jsonapi_type = resource_class.short_model_name.singular

                  resource_class.jsonapi_lock_method(:post) do

                    unless data_ids.empty? || resource_class.included_modules.include?(Zermelo::Records::Stub)
                      conflicted_ids = resource_class.intersect(id_field => data_ids).ids
                      halt(err(409, "#{resource_class.name.split('::').last.pluralize} already exist with the following #{id_field}s: " +
                               conflicted_ids.to_a.join(', '))) unless conflicted_ids.empty?
                    end
                    links_by_resource = resources_data.each_with_object({}) do |rd, memo|
                      record_data = rd['attributes'].nil? ? {} :
                        normalise_json_data(attribute_types, rd['attributes'])
                      type = rd['type']
                      halt(err(409, "Resource missing data type")) if type.nil?
                      halt(err(409, "Resource data type '#{type}' does not match endpoint '#{jsonapi_type}'")) unless jsonapi_type.eql?(type)
                      r_id = case id_field
                      when :id
                        rd['id']
                      else
                        record_data[id_field]
                      end
                      record_data[:id] = r_id unless r_id.nil?
                      r = resource_class.new(record_data)

                      # hacking in support for non-persisted objects
                      case resource_class.name
                      when Flapjack::Data::Acknowledgement.name, Flapjack::Data::TestNotification.name
                        r.queue = config['processor_queue'] || 'events'
                      end

                      halt(err(403, "Validation failed, " + r.errors.full_messages.join(', '))) if r.invalid?
                      memo[r] = rd['relationships']
                    end

                    # get linked objects, fail before save if we don't find them
                    resource_links = links_by_resource.each_with_object({}) do |(r, links), memo|
                      next if links.nil?

                      singular_links.each_pair do |assoc, assoc_klass|
                        next unless links.has_key?(assoc.to_s)
                        memo[r.object_id] ||= {}
                        memo[r.object_id][assoc.to_s] = assoc_klass.data_klass.find_by_id!(links[assoc.to_s]['data']['id'])
                      end

                      multiple_links.each_pair do |assoc, assoc_klass|
                        next unless links.has_key?(assoc.to_s)
                        memo[r.object_id] ||= {}
                        memo[r.object_id][assoc.to_s] = assoc_klass.data_klass.find_by_ids!(*(links[assoc.to_s]['data'].map {|l| l['id']}))
                      end
                    end

                    links_by_resource.keys.each do |r|
                      r.save!
                      rl = resource_links[r.object_id]
                      next if rl.nil?
                      rl.each_pair do |assoc, value|
                        case value
                        when Array
                          r.send(assoc.to_sym).add(*value)
                        else
                          r.send("#{assoc}=".to_sym, value)
                        end
                      end
                    end
                    resources = links_by_resource.keys
                  end

                  resource_ids = resources.map(&:id)

                  response.headers['Location'] = "#{request.base_url}/#{resource}/#{resource_ids.join(',')}"

                  ajs = as_jsonapi(resource_class, resource,
                                   resources, resource_ids,
                                   :unwrap => unwrap, :query_type => :resource)

                  Flapjack.dump_json(ajs)
                end
              end

            end
          end
        end
      end
    end
  end
end
