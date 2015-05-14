#!/usr/bin/env ruby

require 'sinatra/base'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module ResourceDelete

          module Helpers
            def resource_delete(klass, id)
              resources_data, unwrap = wrapped_params(:allow_nil => !id.nil?)

              ids = resources_data.nil? ? [id] : resources_data.map {|d| d['id']}

              klass.lock(*klass.jsonapi_locks(:delete)) do
                if id.nil?
                  resources = klass.intersect(:id => ids)
                  halt(err(404, "Could not find all records to delete")) unless resources.count == ids.size
                  resources.destroy_all
                else
                  halt(err(403, "Id path/data mismatch")) unless ids.eql?([id])
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
            app.helpers Flapjack::Gateways::JSONAPI::Methods::ResourceDelete::Helpers

            Flapjack::Gateways::JSONAPI::RESOURCE_CLASSES.each do |resource_class|
              if resource_class.jsonapi_methods.include?(:delete)
                resource = resource_class.jsonapi_type.pluralize.downcase

                app.class_eval do
                  single = resource.singularize

                  model_type = resource_class.name.demodulize
                  model_type_plural = model_type.pluralize
                  model_type_reference_data_plural = "jsonapi_data_#{model_type_plural}Reference".to_sym

                  swagger_path "/#{resource}/{#{single}_id}" do
                    operation :delete do
                      key :description, "Delete a #{single}"
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
                        key :description, "#{model_type} deletion response"
                      end
                      # response :default do
                      #   key :description, 'unexpected error'
                      #   schema do
                      #     key :'$ref', :ErrorModel
                      #   end
                      # end
                    end
                  end

                  swagger_path "/#{resource}" do
                    operation :delete do
                      key :description, "Delete #{resource}"
                      key :operationId, "delete_#{resource}"
                      key :consumes, [JSONAPI_MEDIA_TYPE_BULK]
                      parameter do
                        key :name, :body
                        key :in, :body
                        key :description, "#{resource} to delete"
                        key :required, true
                        schema do
                          key :'$ref', model_type_reference_data_plural
                        end
                      end
                      response 204 do
                        key :description, "#{resource} deletion response"
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
