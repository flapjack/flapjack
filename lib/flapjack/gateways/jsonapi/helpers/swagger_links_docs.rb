#!/usr/bin/env ruby

require 'active_support/concern'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Helpers
        module SwaggerLinksDocs

          extend ActiveSupport::Concern

          # included do
          # end

          class_methods do

            def swagger_post_links(resource, klass, linked = {})

              single = resource.singularize

              linked.each_pair do |link_name, link_klass|

                link_type = link_klass.name.demodulize

                swagger_path "/#{resource}/{#{single}_id}/links/#{link_name}" do
                  operation :post do
                    key :description, "Associate one or more #{link_name} to a #{single}"
                    key :operationId, "add_#{single}_#{link_name}"
                    key :consumes, [JSONAPI_MEDIA_TYPE]
                    parameter do
                      key :name, "#{single}_id".to_sym
                      key :in, :path
                      key :description, "Id of a #{single}"
                      key :required, true
                      key :type, :string
                    end
                    parameter do
                      key :name, :data
                      key :in, :body
                      key :description, "#{link_name} to associate with the #{single}"
                      key :required, true
                      schema do
                        key :type, :array
                        items do
                          key :"$ref", "#{link_type}Reference".to_sym
                        end
                      end
                    end
                    response 204 do
                      key :description, ''
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

            def swagger_get_links(resource, klass, linked = {})

            end

            def swagger_patch_links(resource, klass, linked = {})

            end

            def swagger_delete_links(resource, klass, linked = {})

            end

          end

        end
      end
    end
  end
end
