#!/usr/bin/env ruby

require 'sinatra/base'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module ResourcePatch

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Resources
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Serialiser

            Flapjack::Gateways::JSONAPI::RESOURCE_CLASSES.each do |resource_class|
              jsonapi_method = resource_class.jsonapi_methods[:patch]

              unless jsonapi_method.nil?

                jsonapi_links = resource_class.jsonapi_associations

                singular_links = jsonapi_links.select {|n, jd|
                  jd.send(:patch).is_a?(TrueClass) && :singular.eql?(jd.number)
                }

                multiple_links = jsonapi_links.select {|n, jd|
                  jd.send(:post).is_a?(TrueClass) && :multiple.eql?(jd.number)
                }

                resource = resource_class.short_model_name.plural

                app.class_eval do
                  single = resource_class.short_model_name.singular

                  model_type = resource_class.short_model_name.name
                  model_type_plural = model_type.pluralize

                  model_type_update = "#{model_type}Update".to_sym

                  swagger_path "/#{resource}/{#{single}_id}" do
                    operation :patch do
                      key :description, jsonapi_method.descriptions[:singular]
                      key :operationId, "update_#{single}"
                      key :consumes, [JSONAPI_MEDIA_TYPE]
                      parameter do
                        key :name, "#{single}_id".to_sym
                        key :in, :path
                        key :description, "Id of a #{single}"
                        key :required, true
                        key :type, :string
                        key :format, :uuid
                      end
                      parameter do
                        key :name, :data
                        key :in, :body
                        key :description, "#{model_type} to update"
                        key :required, true
                        schema do
                          key :"$ref", model_type_update
                        end
                      end
                      response 204 do
                        key :description, "No Content; #{model_type} update success"
                      end
                      response 403 do
                        key :description, "Forbidden; invalid data"
                        schema do
                          key :'$ref', :Errors
                        end
                      end
                      response 404 do
                        key :description, "Not Found"
                        schema do
                          key :'$ref', :Errors
                        end
                      end
                      response 409 do
                        key :description, "Conflict; request id mismatch"
                        schema do
                          key :'$ref', :Errors
                        end
                      end
                    end
                  end

                  swagger_path "/#{resource}" do
                    operation :patch do
                      key :description, jsonapi_method.descriptions[:multiple]
                      key :operationId, "update_#{resource}"
                      key :consumes, [JSONAPI_MEDIA_TYPE_BULK]
                      parameter do
                        key :name, :data
                        key :in, :body
                        key :description, "#{resource} to update"
                        key :required, true
                        schema do
                          key :type, :array
                          items do
                            key :"$ref", model_type_update
                          end
                        end
                      end
                      response 204 do
                        key :description, "No Content; #{resource} update succeeded"
                      end
                      response 403 do
                        key :description, "Forbidden; invalid data"
                        schema do
                          key :'$ref', :Errors
                        end
                      end
                      response 404 do
                        key :description, "Not Found"
                        schema do
                          key :'$ref', :Errors
                        end
                      end
                      response 409 do
                        key :description, "Conflict; request id mismatch"
                        schema do
                          key :'$ref', :Errors
                        end
                      end
                    end
                  end
                end

                app.patch %r{^/#{resource}(?:/(.+))?$} do
                  resource_id = params[:captures].nil? ? nil :
                                  params[:captures].first
                  status 204

                  resources_data, _ = wrapped_params

                  attributes = jsonapi_method.attributes || []

                  validate_data(resources_data, :attributes => attributes,
                    :singular_links => singular_links,
                    :multiple_links => multiple_links)

                  ids = resources_data.map {|d| d['id']}

                  klasses_to_lock = resources_data.inject([]) do |memo, d|
                    next memo unless d.has_key?('relationships')
                    d['relationships'].each_pair do |k, v|
                      assoc = jsonapi_links[k.to_sym]
                      next if assoc.nil?
                      memo |= assoc.lock_klasses
                    end
                    memo
                  end

                  jsonapi_type = resource_class.short_model_name.singular

                  resource_class.jsonapi_lock_method(:patch, klasses_to_lock) do

                    resources = if resource_id.nil?
                      resources = resource_class.find_by_ids!(*ids)
                    else
                      halt(err(409, "Id path/data mismatch")) unless ids.nil? || ids.eql?([resource_id])
                      [resource_class.find_by_id!(resource_id)]
                    end

                    resources_by_id = resources.each_with_object({}) {|r, o| o[r.id] = r }

                    attribute_types = resource_class.attribute_types

                    resource_links = resources_data.each_with_object({}) do |d, memo|
                      r = resources_by_id[d['id']]
                      rd = normalise_json_data(attribute_types, d['attributes'] || {})

                      type = d['type']
                      halt(err(409, "Resource missing data type")) if type.nil?
                      halt(err(409, "Resource data type '#{type}' does not match endpoint type '#{jsonapi_type}'")) unless jsonapi_type.eql?(type)

                      rd.each_pair do |att, value|
                        next unless attributes.include?(att.to_sym)
                        r.send("#{att}=".to_sym, value)
                      end
                      halt(err(403, "Validation failed, " + r.errors.full_messages.join(', '))) if r.invalid?

                      links = d['relationships']
                      next if links.nil?

                      singular_links.each_pair do |assoc, assoc_klass|
                        next unless links.has_key?(assoc.to_s)
                        memo[r.id] ||= {}
                        memo[r.id][assoc.to_s] = assoc_klass.data_klass.find_by_id!(links[assoc.to_s]['data']['id'])
                      end

                      multiple_links.each_pair do |assoc, assoc_klass|
                        next unless links.has_key?(assoc.to_s)
                        current_assoc_ids = r.send(assoc.to_sym).ids.to_a
                        memo[r.id] ||= {}

                        link_ids = links[assoc.to_s]['data'].map {|l| l['id']}

                        to_remove = current_assoc_ids - link_ids
                        to_add    = link_ids - current_assoc_ids

                        memo[r.id][assoc] = [
                          to_remove.empty? ? [] : assoc_klass.data_klass.find_by_ids!(*to_remove),
                          to_add.empty?    ? [] : assoc_klass.data_klass.find_by_ids!(*to_add)
                        ]
                      end
                    end

                    resources_by_id.each do |r_id, r|
                      r.save!
                      rl = resource_links[r_id]
                      next if rl.nil?
                      rl.each_pair do |assoc, value|
                        case value
                        when Array
                          to_remove = value.first
                          to_add    = value.last

                          r.send(assoc.to_sym).remove(*to_remove) unless to_remove.empty?
                          r.send(assoc.to_sym).add(*to_add) unless to_add.empty?
                        else
                          r.send("#{assoc}=".to_sym, value)
                        end
                      end
                    end

                  end

                  true
                end
              end
            end
          end
        end
      end
    end
  end
end
