#!/usr/bin/env ruby

require 'sinatra/base'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module ResourcePost

          # module Helpers
          # end

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Resources
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Serialiser
            # app.helpers Flapjack::Gateways::JSONAPI::Methods::ResourcePost::Helpers

            Flapjack::Gateways::JSONAPI::RESOURCE_CLASSES.each do |resource_class|
              jsonapi_method = resource_class.jsonapi_methods[:post]

              unless jsonapi_method.nil?
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
                  model_type_create = "#{model_type}Create".to_sym
                  model_type_data = "data_#{model_type}".to_sym

                  # TODO how to include plural for same route? swagger won't overload...

                  swagger_path "/#{resource}" do
                    operation :post do
                      key :description, jsonapi_method.descriptions[:singular]
                      key :operationId, "create_#{single}"
                      key :consumes, [JSONAPI_MEDIA_TYPE]
                      key :produces, [Flapjack::Gateways::JSONAPI.media_type_produced]
                      parameter do
                        key :name, :data
                        key :in, :body
                        key :description, "#{single} to create"
                        key :required, true
                        schema do
                          key :"$ref", model_type_create
                        end
                      end
                      response 200 do
                        key :description, "#{single} creation success"
                        schema do
                          key :'$ref', model_type_data
                        end
                      end
                      response 403 do
                        key :description, "Forbidden; invalid data"
                        schema do
                          key :'$ref', :Errors
                        end
                      end
                      response 409 do
                        key :description, "Conflict; bad request structure"
                        schema do
                          key :'$ref', :Errors
                        end
                      end
                    end
                  end

                end

                app.post "/#{resource}" do
                  status 201

                  resources_data, unwrap = wrapped_params

                  attributes = jsonapi_method.attributes || []

                  validate_data(resources_data, :attributes => attributes,
                    :singular_links => singular_links,
                    :multiple_links => multiple_links)

                  resources = nil

                  data_ids = resources_data.each_with_object([]) do |d, memo|
                    d_id = d['id']
                    memo << d_id.to_s unless d_id.nil?
                  end

                  klasses_to_lock = resources_data.inject([]) do |memo, d|
                    next memo unless d.has_key?('relationships')
                    d['relationships'].each_pair do |k, v|
                      assoc = jsonapi_links[k.to_sym]
                      next if assoc.nil?
                      memo |= assoc.lock_klasses
                    end
                    memo
                  end

                  attribute_types = resource_class.attribute_types

                  jsonapi_type = resource_class.short_model_name.singular

                  resource_class.jsonapi_lock_method(:post, klasses_to_lock) do

                    unless data_ids.empty? || resource_class.included_modules.include?(Zermelo::Records::Stub)
                      conflicted_ids = resource_class.intersect(:id => data_ids).ids
                      halt(err(409, "#{resource_class.name.split('::').last.pluralize} already exist with the following ids: " +
                               conflicted_ids.to_a.join(', '))) unless conflicted_ids.empty?
                    end
                    links_by_resource = resources_data.each_with_object({}) do |rd, memo|
                      record_data = rd['attributes'].nil? ? {} :
                        normalise_json_data(attribute_types, rd['attributes'])
                      type = rd['type']
                      halt(err(409, "Resource missing data type")) if type.nil?
                      halt(err(409, "Resource data type '#{type}' does not match endpoint '#{jsonapi_type}'")) unless jsonapi_type.eql?(type)
                      r_id = rd['id']
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
                          r.send(assoc.to_sym).add(*value) unless value.empty?
                        else
                          r.send("#{assoc}=".to_sym, value)
                        end
                      end
                    end
                    resources = links_by_resource.keys
                  end

                  resource_ids = resources.map(&:id)

                  response.headers['Location'] = "#{request.base_url}/#{resource}/#{resource_ids.join(',')}"

                  ajs = as_jsonapi(resource_class, resources, resource_ids,
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
