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

            swagger_schema :Linkage do
              key :required, [:related, :self]
              property :related do
                key :type, :string
                key :format, :url
              end
              property :self do
                key :type, :string
                key :format, :url
              end
            end

            swagger_schema :Links do
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

            swagger_schema :Pagination do
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

            swagger_schema :Meta do
              property :pagination do
                key :"$ref", :Pagination
              end
            end

            swagger_schema :Error do
              property :id do
                key :type, :string
                key :format, :uuid
              end
              property :status do
                key :type, :string
              end
              property :detail do
                key :type, :string
              end
            end

            swagger_schema :Errors do
              property :errors do
                key :type, :array
                items do
                  key :"$ref", :Error
                end
              end
            end
          end

          class_methods do
            def swagger_wrappers(resource, klass)
              jsonapi_methods = if klass.respond_to?(:jsonapi_methods)
                klass.jsonapi_methods || {}
              else
                {}
              end

              singular = Flapjack::Gateways::JSONAPI::RESOURCE_CLASSES.map(&:jsonapi_associations).inject([]) do |memo, assoc|
                memo += assoc.values.select {|ja| klass.eql?(ja.data_klass) && :singular.eql?(ja.number) }
                memo
              end

              multiple = Flapjack::Gateways::JSONAPI::RESOURCE_CLASSES.map(&:jsonapi_associations).inject([]) do |memo, assoc|
                memo += assoc.values.select { |ja| klass.eql?(ja.data_klass) && :multiple.eql?(ja.number) }
                memo
              end

              included_classes = klass.swagger_included_classes

              model_type           = klass.name.demodulize
              model_type_plural    = model_type.pluralize

              model_type_included              = "#{model_type}Included".to_sym

              model_type_create                = jsonapi_methods.key?(:post) ? "#{model_type}Create".to_sym : nil
              model_type_update                = jsonapi_methods.key?(:patch) ? "#{model_type}Update".to_sym : nil

              model_type_data                  = "data_#{model_type}".to_sym
              model_type_data_plural           = "data_#{model_type_plural}".to_sym

              # model_type_create_data           = jsonapi_methods.key?(:post) ? "data_#{model_type_create}".to_sym : nil
              # model_type_create_data_plural  = jsonapi_methods.key?(:post) ? "data_#{model_type_plural}Create".to_sym : nil

              model_type_reference             = "#{model_type}Reference".to_sym
              model_type_reference_data        = "data_#{model_type_reference}".to_sym
              model_type_reference_data_plural = "data_#{model_type_plural}Reference".to_sym

              model_type_linkage               = "#{model_type}Linkage".to_sym
              model_type_linkage_plural        = "#{model_type_plural}Linkage".to_sym

              if included_classes.empty?

                swagger_schema model_type_data do
                  key :required, [:data]
                  property :data do
                    key :"$ref", model_type
                  end
                  property :links do
                    key :"$ref", :Links
                  end
                end

              else
                swagger_schema model_type_included do
                  key :required, [:type, :id]
                  property :type do
                    key :type, :string
                    key :enum, included_classes.map(&:short_model_name).
                      map(&:singular).map(&:to_s)
                  end
                  property :id do
                    key :type, :string
                    key :format, :uuid
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
                      key :"$ref", model_type_included
                    end
                  end
                  property :links do
                    key :"$ref", :Links
                  end
                end
              end

              if [:get, :patch, :delete].any? {|m| jsonapi_methods.key?(m) } ||
                !singular.empty? || !multiple.empty?

                if included_classes.empty?
                  swagger_schema model_type_data_plural do
                    key :required, [:data]
                    property :data do
                      key :type, :array
                      items do
                        key :"$ref", model_type
                      end
                    end
                    property :links do
                      key :"$ref", :Links
                    end
                    property :meta do
                      key :"$ref", :Meta
                    end
                  end
                else
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
                        key :"$ref", model_type_included
                      end
                    end
                    property :links do
                      key :"$ref", :Links
                    end
                    property :meta do
                      key :"$ref", :Meta
                    end
                  end
                end
              end

              deletable = jsonapi_methods.key?(:delete)

              unless singular.empty? && multiple.empty? && !deletable
                singular_ref = singular.any? {|s| [:post, :patch].any? {|r| s.send(r) }}
                singular_lnk = singular.any? {|s| [:post, :get, :patch].any? {|r| s.send(r) }}

                multiple_ref = multiple.any? {|m| [:post, :patch].any? {|r| m.send(r) }}
                multiple_lnk = multiple.any? {|m| [:post, :get, :patch].any? {|r| m.send(r) }}

                if deletable || singular_ref || singular_lnk || multiple_ref || multiple_lnk
                  swagger_schema model_type_reference do
                    key :required, [:id, :type]
                    property :id do
                      key :type, :string
                      key :format, :uuid
                    end
                    property :type do
                      key :type, :string
                      key :enum, [klass.short_model_name.singular]
                    end
                  end
                end

                if singular_ref
                  swagger_schema model_type_reference_data do
                    key :required, [:data]
                    property :data do
                      key :"$ref", model_type_reference
                    end
                  end
                end

                if singular_lnk
                  swagger_schema model_type_linkage do
                    property :links do
                      key :"$ref", :Linkage
                    end
                    property :data do
                      key :"$ref", model_type_reference
                    end
                  end
                end

                if multiple_ref || deletable
                  swagger_schema model_type_reference_data_plural do
                    key :required, [:data]
                    property :data do
                      key :type, :array
                      items do
                        key :"$ref", model_type_reference
                      end
                    end
                  end
                end

                if multiple_lnk
                  swagger_schema model_type_linkage_plural do
                    property :links do
                      key :"$ref", :Linkage
                    end
                    property :data do
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
end
