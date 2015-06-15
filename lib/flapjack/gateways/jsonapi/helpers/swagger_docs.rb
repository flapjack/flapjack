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

              model_type_data = "jsonapi_#{model_type}".to_sym

              model_type_create_data = "jsonapi_data_#{model_type}Create".to_sym
              model_type_update_data = "jsonapi_data_#{model_type}Update".to_sym

              model_type_data_plural           = "jsonapi_#{model_type_plural}".to_sym
              # model_type_create_data_plural    = "jsonapi_data_#{model_type_plural}Create".to_sym
              model_type_update_data_plural    = "jsonapi_data_#{model_type_plural}Update".to_sym
              model_type_reference_data_plural = "jsonapi_#{model_type_plural}Reference".to_sym

              model_type_linkage = "jsonapi_#{model_type}Linkage".to_sym
              model_type_linkage_plural = "jsonapi_#{model_type_plural}Linkage".to_sym

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
                property :relationships do
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
                property :relationships do
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

              unless ['Rule', 'Medium', 'ScheduledMaintenance', 'Tag',
                'UnscheduledMaintenance'].include?(model_type)

                swagger_schema model_type_linkage do
                  key :required, [:linkage]
                  property :linkage do
                    key :"$ref", model_type_reference
                  end
                end
              end

              unless 'Contacts'.eql?(model_type_plural)
                swagger_schema model_type_linkage_plural do
                  key :required, [:linkage]
                  property :linkage do
                    key :type, :array
                    items do
                      key :"$ref", model_type_reference
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
end
