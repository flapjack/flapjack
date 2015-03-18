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
              single = resource.singularize

              model_type = klass.name.demodulize
              model_type_create = "#{model_type}Create".to_sym
              model_type_update = "#{model_type}Update".to_sym
              model_type_reference = "#{model_type}Reference".to_sym

              swagger_type = "jsonapi_#{model_type}".to_sym
              swagger_type_data = "jsonapi_#{model_type}Data".to_sym
              swagger_type_create = "jsonapi_#{model_type}Create".to_sym
              swagger_type_update = "jsonapi_#{model_type}Update".to_sym

              model_type_plural = model_type.pluralize
              swagger_type_plural = "jsonapi_#{model_type_plural}".to_sym
              swagger_type_plural_data = "jsonapi_#{model_type_plural}Data".to_sym
              swagger_type_plural_create = "jsonapi_#{model_type_plural}Create".to_sym
              swagger_type_plural_update = "jsonapi_#{model_type_plural}Update".to_sym

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

              swagger_schema swagger_type_data do
                key :required, [:data]
                property :data do
                  key :"$ref", swagger_type
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

              swagger_schema swagger_type_plural_data do
                key :required, [:data]
                property :data do
                  key :"$ref", swagger_type_plural
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

              swagger_schema swagger_type_create  do
                key :required, [resource.to_sym]
                property resource.to_sym do
                  key :"$ref", model_type_create
                end
              end

              swagger_schema swagger_type_plural_create do
                key :required, [resource.to_sym]
                property resource.to_sym do
                  key :type, :array
                  items do
                    key :"$ref", model_type_create
                  end
                end
              end

              swagger_schema swagger_type do
                key :required, [resource.to_sym]
                property resource.to_sym do
                  key :"$ref", model_type
                end
              end

              swagger_schema swagger_type_plural do
                key :required, [resource.to_sym]
                property resource.to_sym do
                  key :type, :array
                  items do
                    key :"$ref", model_type
                  end
                end
              end

              swagger_schema swagger_type_update  do
                key :required, [resource.to_sym]
                property resource.to_sym do
                  key :"$ref", model_type_update
                end
              end

              swagger_schema swagger_type_plural_update do
                key :required, [resource.to_sym]
                property resource.to_sym do
                  key :type, :array
                  items do
                    key :"$ref", model_type_update
                  end
                end
              end

            end

            def swagger_post(resource, klass)
              single = resource.singularize

              swagger_type_create = "jsonapi_#{klass.name.demodulize}Create".to_sym
              swagger_type_data = "jsonapi_#{klass.name.demodulize}Data".to_sym

              # swagger_type_plural_create = "jsonapi_#{klass.name.demodulize.pluralize}Create".to_sym
              # swagger_type_plural_data = "jsonapi_#{klass.name.demodulize.pluralize}Data".to_sym

              swagger_path "/#{resource}" do
                operation :post do
                  key :description, "Create a #{single}"
                  key :operationId, "create_#{single}"
                  key :consumes, [JSONAPI_MEDIA_TYPE]
                  key :produces, [JSONAPI_MEDIA_TYPE]
                  parameter do
                    key :name, :data
                    key :in, :body
                    key :description, "#{single} to create"
                    key :required, true
                    schema do
                      key :'$ref', swagger_type_create
                    end
                  end
                  response 200 do
                    key :description, "#{single} creation response"
                    schema do
                      key :'$ref', swagger_type_data
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
              swagger_type_plural_data = "jsonapi_#{model_type_plural}Data".to_sym

              swagger_path "/#{resource}" do
                operation :get do
                  key :description, "Get all #{resource}"
                  key :operationId, "get_all_#{resource}"
                  key :produces, [JSONAPI_MEDIA_TYPE]
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
                    key :type, :string
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
                      key :'$ref', swagger_type_plural_data
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

              swagger_path "/#{resource}/{#{single}_ids}" do
                operation :get do
                  key :description, "Get one or more #{resource} by id"
                  key :operationId, "get_#{single}"
                  key :produces, [JSONAPI_MEDIA_TYPE]
                  parameter do
                    key :name, "#{single}_ids".to_sym
                    key :in, :path
                    key :description, 'Comma-separated list of ids'
                    key :required, true
                    key :type, :string
                  end
                  parameter do
                    key :name, :fields
                    key :in, :query
                    key :description, 'Comma-separated list of fields to return'
                    key :required, false
                    key :type, :string
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
              swagger_type_update = "jsonapi_#{model_type}Update".to_sym

              swagger_path "/#{resource}/{#{single}_ids}" do
                operation :patch do
                  key :description, "Update one or more #{resource} by id"
                  key :operationId, "update_#{single}"
                  key :consumes, [JSONAPI_MEDIA_TYPE]
                  parameter do
                    key :name, "#{single}_ids".to_sym
                    key :in, :path
                    key :description, 'Comma-separated list of ids'
                    key :required, true
                    key :type, :string
                  end
                  parameter do
                    key :name, :data
                    key :in, :body
                    key :description, "#{model_type} to update"
                    key :required, true
                    schema do
                      key :'$ref', swagger_type_update
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

              swagger_path "/#{resource}/{#{single}_ids}" do
                operation :delete do
                  key :description, "Delete one or more #{resource} by id"
                  key :operationId, "delete_#{single}"
                  key :consumes, [JSONAPI_MEDIA_TYPE]
                  parameter do
                    key :name, "#{single}_ids".to_sym
                    key :in, :path
                    key :description, 'Comma-separated list of ids'
                    key :required, true
                    key :type, :string
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
            end

          end

        end
      end
    end
  end
end
