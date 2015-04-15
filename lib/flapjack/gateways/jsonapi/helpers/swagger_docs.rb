#!/usr/bin/env ruby

require 'active_support/concern'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Helpers
        module SwaggerDocs

          extend ActiveSupport::Concern

          # included do
          # end

          class_methods do

            def swagger_wrappers(resource, klass)
              model_type           = klass.name.demodulize
              model_type_plural    = model_type.pluralize

              model_type_create    = "#{model_type}Create".to_sym
              model_type_update    = "#{model_type}Update".to_sym
              model_type_reference = "#{model_type}Reference".to_sym

              model_type_data = "jsonapi_data_#{model_type}".to_sym

              model_type_create_data = "jsonapi_data_#{model_type}Create".to_sym
              model_type_update_data = "jsonapi_data_#{model_type}Update".to_sym

              model_type_data_plural           = "jsonapi_data_#{model_type_plural}".to_sym
              # model_type_create_data_plural    = "jsonapi_data_#{model_type_plural}Create".to_sym
              model_type_update_data_plural    = "jsonapi_data_#{model_type_plural}Update".to_sym
              model_type_reference_data_plural = "jsonapi_data_#{model_type_plural}Reference".to_sym

              swagger_schema model_type_reference do
                key :required, [:id, :type]
                property :id do
                  key :type, :string
                  key :format, :uuid
                end
                property :type do
                  key :type, :string
                  key :enum, [model_type.downcase]
                end
              end

              swagger_schema model_type_reference_data_plural do
                key :required, [:data]
                property :data do
                  key :type, :array
                  items do
                    key :"$ref", model_type_reference
                  end
                end
              end

              swagger_schema model_type_data do
                key :required, [:data]
                property :data do
                  key :"$ref", model_type
                end
                property :included do
                  key :type, :array
                  items do
                    key :"$ref", :jsonapi_Reference
                  end
                end
                property :links do
                  key :"$ref", :jsonapi_Links
                end
              end

              swagger_schema model_type_data_plural do
                key :required, [:data]
                property :data do
                  key :type, :array
                  items do
                    key :"$ref", model_type
                  end
                end
                property :included do
                  key :type, :array
                  items do
                    key :"$ref", :jsonapi_Reference
                  end
                end
                property :links do
                  key :"$ref", :jsonapi_Links
                end
                property :meta do
                  key :"$ref", :jsonapi_Meta
                end
              end

              swagger_schema model_type_create_data do
                key :required, [:data]
                property :data do
                  key :"$ref", model_type_create
                end
              end

              # swagger_schema model_type_create_data_plural do
              #   key :required, [:data]
              #   property :data do
              #     key :type, :array
              #     items do
              #       key :"$ref", model_type_create
              #     end
              #   end
              # end

              swagger_schema model_type_update_data do
                key :required, [:data]
                property :data do
                  key :"$ref", model_type_update
                end
              end

              swagger_schema model_type_update_data_plural do
                key :required, [:data]
                property :data do
                  key :type, :array
                  items do
                    key :"$ref", model_type_update
                  end
                end
              end
            end

            def swagger_post(resource, klass)
              single = resource.singularize

              model_type = klass.name.demodulize
              # model_type_create = "#{model_type}Create".to_sym

              model_type_data = "jsonapi_data_#{model_type}".to_sym
              model_type_create_data = "jsonapi_data_#{model_type}Create".to_sym

              # TODO how to include plural for same route?

              swagger_path "/#{resource}" do
                operation :post do
                  key :description, "Create a #{single}"
                  key :operationId, "create_#{single}"
                  key :consumes, [JSONAPI_MEDIA_TYPE]
                  key :produces, [JSONAPI_MEDIA_TYPE_PRODUCED]
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

            def swagger_get(resource, klass)
              single = resource.singularize

              model_type = klass.name.demodulize
              model_type_plural = model_type.pluralize

              model_type_data = "jsonapi_data_#{model_type}".to_sym
              model_type_data_plural = "jsonapi_data_#{model_type_plural}".to_sym

              swagger_path "/#{resource}" do
                operation :get do
                  key :description, "Get all #{resource}"
                  key :operationId, "get_all_#{resource}"
                  key :produces, [JSONAPI_MEDIA_TYPE_PRODUCED]
                  parameter do
                    key :name, :fields
                    key :in, :query
                    key :description, 'Comma-separated list of fields to return'
                    key :required, false
                    key :type, :string
                  end
                  parameter do
                    key :name, :sort
                    key :in, :query
                    key :description, ''
                    key :required, false
                    key :type, :string
                  end
                  parameter do
                    key :name, :filter
                    key :in, :query
                    key :description, ''
                    key :required, false
                    key :type, :array
                    key :collectionFormat, :multi
                    items do
                      key :type, :string
                      key :format, :filter
                    end
                  end
                  parameter do
                    key :name, :include
                    key :in, :query
                    key :description, ''
                    key :required, false
                    key :type, :string
                  end
                  parameter do
                    key :name, :page
                    key :in, :query
                    key :description, 'Page number'
                    key :required, false
                    key :type, :integer
                  end
                  parameter do
                    key :name, :per_page
                    key :in, :query
                    key :description, "Number of #{resource} per page"
                    key :required, false
                    key :type, :integer
                  end
                  response 200 do
                    key :description, "GET #{resource} response"
                    schema do
                      key :'$ref', model_type_data_plural
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

              swagger_path "/#{resource}/{#{single}_id}" do
                operation :get do
                  key :description, "Get a #{single}"
                  key :operationId, "get_#{single}"
                  key :produces, [JSONAPI_MEDIA_TYPE_PRODUCED]
                  parameter do
                    key :name, "#{single}_id".to_sym
                    key :in, :path
                    key :description, "Id of a #{single}"
                    key :required, true
                    key :type, :string
                    key :format, :uuid
                  end
                  parameter do
                    key :name, :fields
                    key :in, :query
                    key :description, 'Comma-separated list of fields to return'
                    key :required, false
                    key :type, :string
                  end
                  response 200 do
                    key :description, "GET #{single} response"
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

            def swagger_patch(resource, klass)
              single = resource.singularize

              model_type = klass.name.demodulize
              model_type_plural = model_type.pluralize

              model_type_data = "jsonapi_data_#{model_type}".to_sym
              model_type_update_data = "jsonapi_data_#{model_type}Update".to_sym

              model_type_update_data_plural = "jsonapi_data_#{model_type_plural}Update".to_sym

              swagger_path "/#{resource}/{#{single}_id}" do
                operation :patch do
                  key :description, "Update a #{single}"
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
                    key :name, :body
                    key :in, :body
                    key :description, "#{model_type} to update"
                    key :required, true
                    schema do
                      key :"$ref", model_type_update_data
                    end
                  end
                  response 204 do
                    key :description, "#{model_type} update response"
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
                operation :patch do
                  key :description, "Update multiple #{resource}"
                  key :operationId, "update_#{resource}"
                  key :consumes, [JSONAPI_MEDIA_TYPE_BULK]
                  parameter do
                    key :name, :body
                    key :in, :body
                    key :description, "#{resource} to update"
                    key :required, true
                    schema do
                      key :"$ref", model_type_update_data_plural
                    end
                  end
                  response 204 do
                    key :description, "#{model_type} update response"
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

            def swagger_delete(resource, klass)
              single = resource.singularize

              model_type = klass.name.demodulize
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

          end

        end
      end
    end
  end
end
