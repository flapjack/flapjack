#!/usr/bin/env ruby

require 'sinatra/base'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module ResourceDelete

          module Helpers
            def resource_delete(klass, id)
              resources_data, _ = wrapped_params(:allow_nil => !id.nil?)

              ids = resources_data.nil? ? [id] : resources_data.map {|d| d['id']}

              klass.jsonapi_lock_method(:delete) do
                if id.nil?
                  resources = klass.intersect(:id => ids)
                  halt(err(404, "Could not find all records to delete")) unless resources.count == ids.size
                  resources.destroy_all
                else
                  klass.find_by_id!(id).destroy
                end
              end

              true
            end
          end

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Resources
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Serialiser
            app.helpers Flapjack::Gateways::JSONAPI::Methods::ResourceDelete::Helpers

            Flapjack::Gateways::JSONAPI::RESOURCE_CLASSES.each do |resource_class|

              jsonapi_method = resource_class.jsonapi_methods[:delete]

              unless jsonapi_method.nil?
                resource = resource_class.short_model_name.plural

                app.class_eval do
                  single = resource_class.short_model_name.singular

                  model_type = resource_class.short_model_name.name

                  swagger_path "/#{resource}/{#{single}_id}" do
                    operation :delete do
                      key :description, jsonapi_method.descriptions[:singular]
                      key :operationId, "delete_#{single}"
                      key :consumes, [JSONAPI_MEDIA_TYPE]
                      parameter do
                        key :name, "#{single}_id".to_sym
                        key :in, :path
                        key :description, "Id of a #{single}"
                        key :required, true
                        key :type, :string
                        key :format, :uuid
                      end
                      response 204 do
                        key :description, "No Content; #{model_type} deletion success"
                      end
                      response 404 do
                        key :description, "Not Found"
                        schema do
                          key :'$ref', :Errors
                        end
                      end
                    end
                  end

                  swagger_path "/#{resource}" do
                    operation :delete do
                      key :description, jsonapi_method.descriptions[:multiple]
                      key :operationId, "delete_#{resource}"
                      key :consumes, [JSONAPI_MEDIA_TYPE_BULK]
                      parameter do
                        key :name, :data
                        key :in, :body
                        key :description, "#{resource} to delete"
                        key :required, true
                        schema do
                          key :type, :array
                          items do
                            key :"$ref", "#{model_type}Reference".to_sym
                          end
                        end
                      end
                      response 204 do
                        key :description, "No Content; #{resource} deletion succeeded"
                      end
                      response 404 do
                        key :description, "Not Found"
                        schema do
                          key :'$ref', :Error
                        end
                      end
                    end
                  end
                end

                app.delete %r{^/#{resource}(?:/(.+))?$} do
                  resource_id = params[:captures].nil? ? nil :
                                  params[:captures].first
                  status 204

                  resource_delete(resource_class, resource_id)
                end
              end
            end
          end
        end
      end
    end
  end
end
