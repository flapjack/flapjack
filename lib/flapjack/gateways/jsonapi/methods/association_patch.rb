#!/usr/bin/env ruby

require 'sinatra/base'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module AssociationPatch

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous

            Flapjack::Gateways::JSONAPI::RESOURCE_CLASSES.each do |resource_class|
              resource = resource_class.jsonapi_type.pluralize.downcase

              jsonapi_links = resource_class.jsonapi_association_links(:read_write)

              assocs       = jsonapi_links[:singular].empty? ? nil : jsonapi_links[:singular].keys.map(&:to_s).join('|')
              multi_assocs = jsonapi_links[:multiple].empty? ? nil : jsonapi_links[:multiple].keys.map(&:to_s).join('|')

              if assocs.nil?
                assocs = multi_assocs
              elsif !multi_assocs.nil?
                assocs += "|#{multi_assocs}"
              end

              unless assocs.nil?
                app.class_eval do
                  # GET and PATCH duplicate a lot of swagger code, but swagger-blocks
                  # make it difficult to DRY things due to the different contexts in use

                  single = resource.singularize

                  jsonapi_links[:singular].each_pair do |link_name, link_data|
                    link_type = link_data[:type]
                    swagger_path "/#{resource}/{#{single}_id}/links/#{link_name}" do
                      operation :patch do
                        key :description, "Replace associated #{link_name} for a #{single}"
                        key :operationId, "replace_#{single}_#{link_name}"
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
                          key :description, "#{link_name} association to replace for the #{single}"
                          key :required, true
                          schema do
                            key :"$ref", "#{link_type}Reference".to_sym
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

                  jsonapi_links[:multiple].each_pair do |link_name, link_data|
                    link_type = link_data[:type]
                    swagger_path "/#{resource}/{#{single}_id}/links/#{link_name}" do
                      operation :patch do
                        key :description, "Replace associated #{link_name} for a #{single}"
                        key :operationId, "replace_#{single}_#{link_name}"
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
                          key :description, "#{link_name} associations to replace for the #{single}"
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

                app.patch %r{^/#{resource}/(#{id_patt})/links/(#{assocs})$} do
                  resource_id = params[:captures][0]
                  assoc_name  = params[:captures][1]

                  status 204

                  singular_klass = jsonapi_links[:singular][assoc_name.to_sym]
                  multiple_klass = jsonapi_links[:multiple][assoc_name.to_sym]

                  assoc_ids, _ = wrapped_link_params(:singular => singular_klass,
                    :multiple => multiple_klass, :allow_nil => true)

                  sk_or_mk = singular_klass || multiple_klass
                  assoc_classes = [sk_or_mk[:data]] + sk_or_mk[:related]
                  resource_class.lock(*assoc_classes) do

                    resource = resource_class.find_by_id!(resource_id)

                    if !multiple_klass.nil?
                      assoc_classes = [multiple_klass[:data]] + multiple_klass[:related]
                      current_assoc_ids = resource.send(assoc_name.to_sym).ids
                      to_remove = current_assoc_ids - assoc_ids
                      to_add    = assoc_ids - current_assoc_ids
                      tr = to_remove.empty? ? [] : multiple_klass[:data].find_by_ids!(*to_remove)
                      ta = to_add.empty?    ? [] : multiple_klass[:data].find_by_ids!(*to_add)
                      resource.send(assoc_name.to_sym).delete(*tr) unless tr.empty?
                      resource.send(assoc_name.to_sym).add(*ta) unless ta.empty?
                    elsif !singular_klass.nil?
                      if assoc_ids.nil?
                        assoc_classes = [singular_klass[:data]] + singular_klass[:related]
                        resource.send("#{assoc_name}=".to_sym, nil)
                      else
                        halt(err(409, "Trying to add multiple records to singular association '#{assoc_name}'")) if assoc_ids.size > 1
                        assoc_classes = [singular_klass[:data]] + singular_klass[:related]
                        value = assoc_ids.first.nil? ? nil : singular_klass[:data].find_by_id!(assoc_ids.first)
                        resource.send("#{assoc_name}=".to_sym, value)
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
