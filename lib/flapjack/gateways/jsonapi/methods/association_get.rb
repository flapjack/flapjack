#!/usr/bin/env ruby

require 'sinatra/base'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module AssociationGet

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous

            Flapjack::Gateways::JSONAPI::RESOURCE_CLASSES.each do |resource_class|
              singular_links, multiple_links = resource_class.association_klasses

              assocs       = singular_links.empty? ? nil : singular_links.keys.map(&:to_s).join('|')
              multi_assocs = multiple_links.empty? ? nil : multiple_links.keys.map(&:to_s).join('|')

              if assocs.nil?
                assocs = multi_assocs
              elsif !multi_assocs.nil?
                assocs += "|#{multi_assocs}"
              end

              unless assocs.nil?
                resource = resource_class.jsonapi_type.pluralize.downcase

                app.class_eval do
                  # GET and PATCH duplicate a lot of swagger code, but swagger-blocks
                  # make it difficult to DRY things due to the different contexts in use
                  single = resource.singularize

                  singular_links.each_pair do |link_name, link_data|
                    link_type = link_data[:type]
                    swagger_path "/#{resource}/{#{single}_id}/#{link_name}" do
                      operation :get do
                        key :description, "Get the #{link_name} of a #{single}"
                        key :operationId, "get_#{single}_#{link_name}"
                        key :produces, [Flapjack::Gateways::JSONAPI.media_type_produced]
                        parameter do
                          key :name, "#{single}_id".to_sym
                          key :in, :path
                          key :description, "Id of a #{single}"
                          key :required, true
                          key :type, :string
                        end
                        response 200 do
                          key :description, "GET #{resource} response"
                          schema do
                            key :"$ref", "#{link_type}Reference".to_sym
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

                    swagger_path "/#{resource}/{#{single}_id}/links/#{link_name}" do
                      operation :get do
                        key :description, "Get the #{link_name} of a #{single}"
                        key :operationId, "get_#{single}_#{link_name}"
                        key :produces, [JSONAPI_MEDIA_TYPE]
                        parameter do
                          key :name, "#{single}_id".to_sym
                          key :in, :path
                          key :description, "Id of a #{single}"
                          key :required, true
                          key :type, :string
                        end
                        response 200 do
                          key :description, "GET #{resource} response"
                          schema do
                            key :"$ref", "#{link_type}Reference".to_sym
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

                  multiple_links.each_pair do |link_name, link_data|
                    link_type = link_data[:type]
                    swagger_path "/#{resource}/{#{single}_id}/#{link_name}" do
                      operation :get do
                        key :description, "Get the #{link_name} of a #{single}"
                        key :operationId, "get_#{single}_#{link_name}"
                        key :produces, [Flapjack::Gateways::JSONAPI.media_type_produced]
                        parameter do
                          key :name, "#{single}_id".to_sym
                          key :in, :path
                          key :description, "Id of a #{single}"
                          key :required, true
                          key :type, :string
                        end
                        response 200 do
                          key :description, "GET #{resource} response"
                          schema do
                            key :type, :array
                            items do
                              key :"$ref", "#{link_type}Reference".to_sym
                            end
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
                    swagger_path "/#{resource}/{#{single}_id}/links/#{link_name}" do
                      operation :get do
                        key :description, "Get the #{link_name} of a #{single}"
                        key :operationId, "get_#{single}_links_#{link_name}"
                        key :produces, [Flapjack::Gateways::JSONAPI.media_type_produced]
                        parameter do
                          key :name, "#{single}_id".to_sym
                          key :in, :path
                          key :description, "Id of a #{single}"
                          key :required, true
                          key :type, :string
                        end
                        response 200 do
                          key :description, "GET #{resource} response"
                          schema do
                            key :type, :array
                            items do
                              key :"$ref", "#{link_type}Reference".to_sym
                            end
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
                end

                id_patt = if Flapjack::Data::Tag.eql?(resource_class)
                  "\\S+"
                else
                  Flapjack::UUID_RE
                end

                app.get %r{^/#{resource}/(#{id_patt})/(?:links/)?(#{assocs})} do
                  resource_id = params[:captures][0]
                  assoc_name  = params[:captures][1]

                  status 200

                  accessor, assoc_type = if multiple_links.has_key?(assoc_name.to_sym)
                    [:ids, multiple_links[assoc_name.to_sym][:data].jsonapi_type]
                  elsif singular_links.has_key?(assoc_name.to_sym)
                    [:id, singular_links[assoc_name.to_sym][:data].jsonapi_type]
                  else
                    halt(err(404, 'Unknown association'))
                  end

                  associated = resource_class.find_by_id!(resource_id).send(assoc_name.to_sym).send(accessor)

                  links = {
                    :self    => "#{request.base_url}/#{resource}/#{resource_id}/links/#{assoc_name}",
                    :related => "#{request.base_url}/#{resource}/#{resource_id}/#{assoc_name}"
                  }

                  data = case associated
                  when Array
                    associated.map {|assoc_id| {:type => assoc_type, :id => assoc_id} }
                  when String
                    {:type => assoc_type, :id => associated}
                  else
                    nil
                  end

                  Flapjack.dump_json(:links => links, :data => data)
                end
              end
            end
          end
        end
      end
    end
  end
end
