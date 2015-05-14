#!/usr/bin/env ruby

require 'sinatra/base'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module ResourceGet

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Resources

            Flapjack::Gateways::JSONAPI::RESOURCE_CLASSES.each do |resource_class|
              if resource_class.jsonapi_methods.include?(:get)
                resource = resource_class.jsonapi_type.pluralize.downcase

                app.class_eval do
                  single = resource.singularize

                  model_type = resource_class.name.demodulize
                  model_type_plural = model_type.pluralize

                  model_type_data = "jsonapi_data_#{model_type}".to_sym
                  model_type_data_plural = "jsonapi_data_#{model_type_plural}".to_sym

                  swagger_path "/#{resource}" do
                    operation :get do
                      key :description, "Get all #{resource}"
                      key :operationId, "get_all_#{resource}"
                      key :produces, [Flapjack::Gateways::JSONAPI.media_type_produced]
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
                        key :type, :array
                        key :collectionFormat, :multi
                        items do
                          key :type, :string
                          key :format, :filter
                        end
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
                          key :'$ref', model_type_data_plural
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

                  swagger_path "/#{resource}/{#{single}_id}" do
                    operation :get do
                      key :description, "Get a #{single}"
                      key :operationId, "get_#{single}"
                      key :produces, [Flapjack::Gateways::JSONAPI.media_type_produced]
                      parameter do
                        key :name, "#{single}_id".to_sym
                        key :in, :path
                        key :description, "Id of a #{single}"
                        key :required, true
                        key :type, :string
                        key :format, :uuid
                      end
                      parameter do
                        key :name, :fields
                        key :in, :query
                        key :description, 'Comma-separated list of fields to return'
                        key :required, false
                        key :type, :string
                      end
                      response 200 do
                        key :description, "GET #{single} response"
                        schema do
                          key :'$ref', model_type_data
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

                app.get %r{^/#{resource}(?:/(.+))?$} do
                  resource_id = params[:captures].nil? ? nil :
                                  params[:captures].first
                  status 200

                  resources, links, meta = if resource_id.nil?
                    scoped = resource_filter_sort(resource_class,
                     :filter => params[:filter], :sort => params[:sort])
                    resource_class.lock(*resource_class.jsonapi_locks(:get)) do
                      paginate_get(scoped, :page => params[:page],
                        :per_page => params[:per_page])
                    end
                  else
                    resource_class.lock(*resource_class.jsonapi_locks(:get)) do
                      [[resource_class.find_by_id!(resource_id)], {}, {}]
                    end
                  end

                  links[:self] = request_url

                  json_data = {:links => links}
                  if resources.empty?
                    json_data[:data] = []
                  else
                    fields = params[:fields].nil?  ? nil : params[:fields].split(',')
                    incl   = params[:include].nil? ? nil : params[:include].split(',')
                    data, included = as_jsonapi(resource_class, resource_class.jsonapi_type,
                                                resource, resources,
                                                (resource_id.nil? ? resources.map(&:id) : [resource_id]),
                                                :fields => fields, :include => incl,
                                                :unwrap => !resource_id.nil?)

                    json_data[:data] = data
                    json_data[:included] = included unless included.nil? || included.empty?
                    json_data[:meta] = meta unless meta.nil? || meta.empty?
                  end
                  Flapjack.dump_json(json_data)
                end
              end
            end
          end
        end
      end
    end
  end
end
