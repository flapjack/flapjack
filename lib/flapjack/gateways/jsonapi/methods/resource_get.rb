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
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Serialiser

            Flapjack::Gateways::JSONAPI::RESOURCE_CLASSES.each do |resource_class|

              jsonapi_method = resource_class.jsonapi_methods[:get]

              unless jsonapi_method.nil?
                resource = resource_class.short_model_name.plural

                app.class_eval do
                  single = resource_class.short_model_name.singular

                  model_type = resource_class.short_model_name.name
                  model_type_plural = model_type.pluralize

                  model_type_data = "data_#{model_type}".to_sym
                  model_type_data_plural = "data_#{model_type_plural}".to_sym

                  swagger_path "/#{resource}" do
                    operation :get do
                      key :description, jsonapi_method.descriptions[:multiple]
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
                        key :description, "GET #{resource} success"
                        schema do
                          key :'$ref', model_type_data_plural
                        end
                      end
                    end
                  end

                  swagger_path "/#{resource}/{#{single}_id}" do
                    operation :get do
                      key :description, jsonapi_method.descriptions[:singular]
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
                      response 404 do
                        key :description, "Not Found"
                        schema do
                          key :'$ref', :Errors
                        end
                      end
                    end
                  end
                end

                # FIXME return 400 if any 'include' param path not recognised

                app.get %r{^/#{resource}(?:/(.+))?$} do
                  resource_id = params[:captures].nil? ? nil :
                                  params[:captures].first
                  incl = params[:include].nil? ? nil : params[:include].split(',')

                  locks = (incl.nil? || incl.empty?) ? [] :
                    lock_for_include_clause(resource_class, :include => incl.dup)

                  status 200

                  json_data = {}

                  resource_class.jsonapi_lock_method(:get, locks) do
                    resources, links, meta = if resource_id.nil?
                      scoped = resource_filter_sort(resource_class,
                       :filter => params[:filter], :sort => params[:sort])
                      paginate_get(scoped, :page => params[:page],
                        :per_page => params[:per_page])
                    else
                      [resource_class.intersect(:id => Set.new([resource_id])), {}, {}]
                    end

                    links[:self] = request_url

                    json_data[:links] = links

                    if resources.empty?
                      if resource_id.nil?
                        json_data[:data] = []
                      else
                        raise ::Zermelo::Records::Errors::RecordNotFound.new(resource_class, resource_id)
                      end
                    else
                      d = as_jsonapi(resource_class, resources,
                                     (resource_id.nil? ? resources.ids : Set.new([resource_id])),
                                     :fields => params[:fields], :include => incl,
                                     :unwrap => !resource_id.nil?, :query_type => :resource)

                      json_data[:data] = d[:data]
                      unless d[:included].nil? || d[:included].empty?
                        json_data[:included] = d[:included]
                      end
                      json_data[:meta] = meta unless meta.nil? || meta.empty?
                    end
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
