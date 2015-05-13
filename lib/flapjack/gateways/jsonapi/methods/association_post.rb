#!/usr/bin/env ruby

require 'sinatra/base'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module AssociationPost

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous

            Flapjack::Gateways::JSONAPI::RESOURCE_CLASSES.each do |resource_class|
              resource = resource_class.jsonapi_type.pluralize.downcase

              _, multiple_links = resource_class.association_klasses(:read_write)

              multi_assocs = multiple_links.empty? ? nil : multiple_links.keys.map(&:to_s).join('|')

              unless multi_assocs.nil?
                app.class_eval do

                  single = resource.singularize

                  multiple_links.each_pair do |link_name, link_data|
                    link_type = link_data[:type]

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

                id_patt = if Flapjack::Data::Tag.eql?(resource_class)
                  "\\S+"
                else
                  Flapjack::UUID_RE
                end

                app.post %r{^/#{resource}/(#{id_patt})/links/(#{multi_assocs})$} do
                  resource_id = params[:captures][0]
                  assoc_name  = params[:captures][1]

                  status 204

                  multiple_klass = multiple_links[assoc_name.to_sym]

                  assoc_ids, _ = wrapped_link_params(:multiple => multiple_klass)

                  halt(err(403, 'No link ids')) if assoc_ids.empty?

                  resource_obj = resource_class.find_by_id!(resource_id)

                  # Not checking for duplication on adding existing to a multiple
                  # association, the JSONAPI spec doesn't ask for it
                  if multiple_klass.nil?
                    # TODO ensure wrapped_link_params will make this unreachable, remove
                  else
                    assoc_classes = [multiple_klass[:data]] + multiple_klass[:related]
                    resource_class.lock(*assoc_classes) do
                      associated = multiple_klass[:data].find_by_ids!(*assoc_ids)
                      resource_obj.send(assoc_name.to_sym).add(*associated)
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
