#!/usr/bin/env ruby

require 'active_support/concern'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Helpers
        module SwaggerDocs

          extend ActiveSupport::Concern

          included do
            swagger_root do
              key :swagger, '2.0'
              info do
                key :version, '2.0.0'
                key :title, 'Flapjack API'
                key :description, ''
                contact do
                  key :name, ''
                end
                license do
                  key :name, 'MIT'
                end
              end
              key :host, 'localhost'
              key :basePath, '/doc'
              key :schemes, ['http']
              key :consumes, [JSONAPI_MEDIA_TYPE]
              key :produces, [JSONAPI_MEDIA_TYPE]
            end

            swagger_schema :jsonapi_Reference do
              key :required, [:type, :id]
              property :type do
                key :type, :string
                key :enum, Flapjack::Gateways::JSONAPI::RESOURCE_CLASSES.map(&:jsonapi_type)
              end
              property :id do
                key :type, :string
                key :format, :uuid
              end
            end

            swagger_schema :jsonapi_Links do
              key :required, [:self]
              property :self do
                key :type, :string
                key :format, :url
              end
              property :first do
                key :type, :string
                key :format, :url
              end
              property :last do
                key :type, :string
                key :format, :url
              end
              property :next do
                key :type, :string
                key :format, :url
              end
              property :prev do
                key :type, :string
                key :format, :url
              end
            end

            swagger_schema :jsonapi_Pagination do
              key :required, [:page, :per_page, :total_pages, :total_count]
              property :page do
                key :type, :integer
                key :format, :int64
              end
              property :per_page do
                key :type, :integer
                key :format, :int64
              end
              property :total_pages do
                key :type, :integer
                key :format, :int64
              end
              property :total_count do
                key :type, :integer
                key :format, :int64
              end
            end

            swagger_schema :jsonapi_Meta do
              property :pagination do
                key :"$ref", :jsonapi_Pagination
              end
            end
          end

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
          end
        end
      end
    end
  end
end
