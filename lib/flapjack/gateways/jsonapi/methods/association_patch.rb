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
              resource = resource_class.short_model_name.plural

              jsonapi_links = if resource_class.respond_to?(:jsonapi_associations)
                resource_class.jsonapi_associations || {}
              else
                {}
              end

              singular_links = jsonapi_links.select {|n, jd|
                jd.link.is_a?(TrueClass) && jd.patch.is_a?(TrueClass) && :singular.eql?(jd.number)
              }

              multiple_links = jsonapi_links.select {|n, jd|
                jd.link.is_a?(TrueClass) && jd.patch.is_a?(TrueClass) && :multiple.eql?(jd.number)
              }

              unless singular_links.empty? && multiple_links.empty?

                app.class_eval do
                  # GET and PATCH duplicate a lot of swagger code, but swagger-blocks
                  # make it difficult to DRY things due to the different contexts in use

                  single = resource.singularize

                  singular_links.each_pair do |link_name, link_data|
                    link_type = link_data.data_klass.short_model_name.name
                    swagger_path "/#{resource}/{#{single}_id}/relationships/#{link_name}" do
                      operation :patch do
                        key :description, link_data.descriptions[:patch]
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
                          key :description, 'No Content; link update success'
                        end
                        response 403 do
                          key :description, "Forbidden; no link id"
                          schema do
                            key :'$ref', :Errors
                          end
                        end
                        response 404 do
                          key :description, "Not Found"
                          schema do
                            key :'$ref', :Errors
                          end
                        end
                      end
                    end
                  end

                  multiple_links.each_pair do |link_name, link_data|
                    link_type = link_data.data_klass.short_model_name.name
                    swagger_path "/#{resource}/{#{single}_id}/relationships/#{link_name}" do
                      operation :patch do
                        key :description, link_data.descriptions[:patch]
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
                          key :description, 'No Content; link update succeeded'
                        end
                        response 403 do
                          key :description, "Forbidden; no link ids"
                          schema do
                            key :'$ref', :Errors
                          end
                        end
                        response 404 do
                          key :description, "Not Found"
                          schema do
                            key :'$ref', :Errors
                          end
                        end
                      end
                    end
                  end
                end

              end

              id_patt = if Flapjack::Data::Tag.eql?(resource_class)
                "\\S+"
              else
                Flapjack::UUID_RE
              end

              assoc_patt = jsonapi_links.keys.map(&:to_s).join("|")

              app.patch %r{^/#{resource}/(#{id_patt})/relationships/(#{assoc_patt})$} do
                resource_id = params[:captures][0]
                assoc_name  = params[:captures][1].to_sym

                halt(404) unless singular_links.has_key?(assoc_name) ||
                  multiple_links.has_key?(assoc_name)

                status 204

                assoc = jsonapi_links[assoc_name]

                assoc_ids, _ = wrapped_link_params(:association => assoc,
                  :allow_nil => true)

                resource_class.lock(*assoc.lock_klasses) do
                  resource = resource_class.find_by_id!(resource_id)

                  if :multiple.eql?(assoc.number)
                    current_assoc_ids = resource.send(assoc_name).ids.to_a
                    to_remove = current_assoc_ids - assoc_ids
                    to_add    = assoc_ids - current_assoc_ids
                    resource.send(assoc_name).remove_ids(*to_remove) unless to_remove.empty?
                    resource.send(assoc_name).add_ids(*to_add) unless to_add.empty?
                  elsif :singular.eql?(assoc.number)
                    if assoc_ids.nil?
                      resource.send("#{assoc_name}=".to_sym, nil)
                    else
                      halt(err(403, "Trying to add multiple records to singular association '#{assoc_name}'")) if assoc_ids.size > 1
                      value = assoc_ids.first.nil? ? nil : assoc.data_klass.find_by_id!(assoc_ids.first)
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
