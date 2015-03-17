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
              model_type_input = "#{model_type}Input".to_sym
              swagger_type = "jsonapi_#{model_type}".to_sym
              swagger_type_data = "jsonapi_#{model_type}Data".to_sym
              swagger_type_input = "jsonapi_#{model_type}Input".to_sym

              model_type_plural = model_type.pluralize
              swagger_type_plural = "jsonapi_#{model_type_plural}".to_sym
              swagger_type_plural_data = "jsonapi_#{model_type_plural}Data".to_sym
              swagger_type_plural_input = "jsonapi_#{model_type_plural}Input".to_sym

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

              swagger_schema swagger_type_input  do
                key :required, [resource.to_sym]
                property resource.to_sym do
                  key :"$ref", model_type_input
                end
              end

              swagger_schema swagger_type_plural_input do
                key :required, [resource.to_sym]
                property resource.to_sym do
                  key :type, :array
                  items do
                    key :"$ref", model_type_input
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

            end

            def swagger_post(resource, klass)
              # swagger_type_input = "jsonapi_#{klass.name.demodulize.pluralize}Input".to_sym
              # swagger_type_data = "jsonapi_#{klass.name.demodulize.pluralize}Data".to_sym

              single = resource.singularize
              swagger_type_input_single = "jsonapi_#{klass.name.demodulize}Input".to_sym
              swagger_type_data_single = "jsonapi_#{klass.name.demodulize}Data".to_sym

              swagger_path "/#{resource}" do
                operation :post do
                  key :description, "Create a #{single}"
                  key :operationId, "create_#{single}"
                  key :consumes, [
                    JSONAPI_MEDIA_TYPE
                  ]
                  key :produces, [
                    JSONAPI_MEDIA_TYPE
                  ]
                  parameter do
                    key :name, :data
                    key :in, :body
                    key :description, "#{single} to create"
                    key :required, true
                    schema do
                      key :'$ref', swagger_type_input_single
                    end
                  end
                  response 200 do
                    key :description, "#{single} creation response"
                    schema do
                      key :'$ref', swagger_type_data_single
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

              # swagger_api_root resource.to_sym do
              #   key :swagger, '2.0'
              #   key :apiVersion, '2.0.0'
              #   key :basePath, '/'
              #   key :resourcePath, "/#{resource}"
              #   api do
              #     key :path, "/#{resource}"
              #     operation do
              #       key :method, 'POST'
              #       key :summary, "Create a #{single}"
              #       key :nickname, "create_#{single}".to_sym
              #       # key :notes, ''
              #       key :consumes, [
              #         JSONAPI_MEDIA_TYPE
              #       ]
              #       key :produces, [
              #         JSONAPI_MEDIA_TYPE
              #       ]
              #       key :"$ref", swagger_type_single
              #       parameter do
              #         key :paramType, :form
              #         key :name, resource.to_sym
              #         key :description, "#{single} object to add"
              #         key :required, true
              #         key :type, swagger_type_single
              #       end
              #       # TODO valid responses
              #     end
              #   end
              # end
            end

            def swagger_get(resource, klass)
              swagger_type = "jsonapi_#{klass.name.demodulize}".to_sym
              swagger_type_single = "jsonapi_#{klass.name.demodulize.singularize}".to_sym
              single = resource.singularize

              # swagger_api_root resource.to_sym do
              #   key :swaggerVersion, '1.2'
              #   key :apiVersion, '2.0.0'
              #   key :basePath, '/'
              #   key :resourcePath, "/#{resource}"
              #   api do
              #     key :path, "/#{resource}"
              #     operation do
              #       key :method, 'GET'
              #       key :summary, "Get all #{resource}"
              #       # key :notes, ''
              #       key :nickname, "get_#{resource}".to_sym
              #       key :produces, [
              #         JSONAPI_MEDIA_TYPE
              #       ]
              #       key :'$ref', swagger_type
              #       parameter do
              #         key :paramType, :query
              #         key :name, :page
              #         key :description, 'Page number'
              #         key :required, false
              #         key :type, :integer
              #       end
              #       parameter do
              #         key :paramType, :query
              #         key :name, :per_page
              #         key :description, "Number of #{resource} per page"
              #         key :required, false
              #         key :type, :integer
              #       end
              #       parameter do
              #         key :paramType, :query
              #         key :name, :fields
              #         key :description, 'Comma-separated list of fields to return'
              #         key :required, false
              #         key :type, :string
              #       end
              #       parameter do
              #         key :paramType, :query
              #         key :name, :include
              #         key :description, 'Comma-separated list of linked associations to include'
              #         key :required, false
              #         key :type, :string
              #       end
              #       parameter do
              #         key :paramType, :query
              #         key :name, :sort
              #         key :description, 'Comma-separated list of fields to sort on; each term must be prepended by + or -'
              #         key :required, false
              #         key :type, :string
              #       end
              #     end
              #   end

              #   api do
              #     key :path, "/#{resource}/{id}"
              #     operation do
              #       key :method, 'GET'
              #       key :summary, "Find #{single} by ID"
              #       key :notes, "Returns a #{single} based on ID"
              #       key :nickname, "get_#{single}"
              #       key :produces, [
              #         JSONAPI_MEDIA_TYPE
              #       ]
              #       key :"$ref", swagger_type_single
              #       parameter do
              #         key :paramType, :path
              #         key :name, :id
              #         key :description, "Comma-separated IDs of #{resource} to be retrieved"
              #         key :required, true
              #         key :type, :string
              #       end
              #       response_message do
              #         key :code, 404
              #         key :message, "#{single} not found"
              #       end
              #     end
              #   end

              # end
            end

            def swagger_patch(resource, klass)

            end

            def swagger_delete(resource, klass)

            end

          end

        end
      end
    end
  end
end
