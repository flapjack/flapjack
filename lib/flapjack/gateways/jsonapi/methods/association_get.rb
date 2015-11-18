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
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Serialiser

            Flapjack::Gateways::JSONAPI::RESOURCE_CLASSES.each do |resource_class|

              jsonapi_links = if resource_class.respond_to?(:jsonapi_associations)
                resource_class.jsonapi_associations || {}
              else
                {}
              end

              singular_links = jsonapi_links.select {|n, jd|
                jd.link.is_a?(TrueClass) && jd.get.is_a?(TrueClass) && :singular.eql?(jd.number)
              }

              multiple_links = jsonapi_links.select {|n, jd|
                jd.link.is_a?(TrueClass) && jd.get.is_a?(TrueClass) && :multiple.eql?(jd.number)
              }

              resource = resource_class.short_model_name.plural

              unless singular_links.empty? && multiple_links.empty?

                app.class_eval do
                  # GET and PATCH duplicate a lot of swagger code, but swagger-blocks
                  # make it difficult to DRY things due to the different contexts in use
                  single = resource.singularize

                  singular_links.each_pair do |link_name, link_data|
                    link_type = link_data.data_klass.short_model_name.name

                    swagger_path "/#{resource}/{#{single}_id}/#{link_name}" do
                      operation :get do
                        key :description, link_data.descriptions[:get]
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
                          key :description, "GET #{resource} #{link_name} success"
                          schema do
                            key :"$ref", "#{link_type}Reference".to_sym
                          end
                        end
                        response 403 do
                          key :description, "Forbidden; invalid request"
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

                    swagger_path "/#{resource}/{#{single}_id}/relationships/#{link_name}" do
                      operation :get do
                        key :description, link_data.descriptions[:get]
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
                          key :description, "GET #{resource} success"
                          schema do
                            key :"$ref", "#{link_type}Reference".to_sym
                          end
                        end
                        response 403 do
                          key :description, "Forbidden; invalid request"
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
                    swagger_path "/#{resource}/{#{single}_id}/#{link_name}" do
                      operation :get do
                        key :description, link_data.descriptions[:get]
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
                        response 403 do
                          key :description, "Forbidden; invalid request"
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
                    swagger_path "/#{resource}/{#{single}_id}/relationships/#{link_name}" do
                      operation :get do
                        key :description, link_data.descriptions[:get]
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
                        response 403 do
                          key :description, "Forbidden; invalid request"
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

              assoc_patt = jsonapi_links.keys.map(&:to_s).join("|")

              app.get %r{^/#{resource}/(#{Flapjack::UUID_RE})/(?:relationships/)?(#{assoc_patt})(\?.+)?} do
                resource_id = params[:captures][0]
                assoc_name  = params[:captures][1].to_sym

                halt(404) unless singular_links.has_key?(assoc_name) ||
                  multiple_links.has_key?(assoc_name)

                fields = params[:fields]
                incl   = params[:include].nil? ? nil : params[:include].split(',')

                assoc = jsonapi_links[assoc_name]

                extra_locks = incl.nil? ? [] : lock_for_include_clause(resource_class,
                        :include => incl.dup)

                locks = assoc.lock_klasses | extra_locks
                locks.sort_by!(&:name)

                status 200

                halt(err(404, 'Unknown relationship')) if assoc.nil?

                empty = false
                included = nil
                result = nil
                meta = nil

                resource_class.lock(*locks) do
                  res = resource_class.intersect(:id => resource_id)
                  empty = res.empty?

                  unless empty
                    associated = res.all.first.send(assoc_name)

                    result = case assoc.number
                    when :multiple

                      unless params[:filter].nil?
                        unless params[:filter].is_a?(Array)
                          halt(err(403, "Filter parameters must be passed as an Array"))
                        end

                        bad = params[:filter].detect {|f| f !~ /^#{assoc_name}\.(?:[^,]+)$/ }
                        unless bad.nil?
                          halt(err(403, "Filter params must start with '#{assoc_name}.', not contain comma: '#{bad}'"))
                        end

                        filters = params[:filter].collect do |f|
                          f.sub(/^#{assoc_name}\./, '')
                        end

                        filter_ops = filter_params(assoc.data_klass, filters)

                        associated = associated.intersect(filter_ops)
                      end

                      associated = associated.sort(:id => :asc)

                      resources, _, meta = paginate_get(associated, :page => params[:page],
                        :per_page => params[:per_page])

                      result = resources.eql?([]) ? [] : resources.ids
                    when :singular
                      result = associated.id
                    end

                    unless incl.nil?
                      included = as_jsonapi_included(resource_class, res,
                        :include => incl, :fields => fields, :query_type => :association)
                    end
                  end
                end
                raise ::Zermelo::Records::Errors::RecordNotFound.new(resource_class, resource_id) if empty

                links = {
                  :self    => "#{request.base_url}/#{resource}/#{resource_id}/relationships/#{assoc_name}",
                  :related => "#{request.base_url}/#{resource}/#{resource_id}/#{assoc_name}"
                }

                data = case result
                when Array, Set
                  result.map {|assoc_id| {:type => assoc.type, :id => assoc_id} }
                when String
                  {:type => assoc.type, :id => result}
                else
                  nil
                end

                ret = {:data => data, :links => links}
                ret[:included] = included unless included.nil?
                ret[:meta] = meta unless meta.nil?
                Flapjack.dump_json(ret)
              end
            end
          end
        end
      end
    end
  end
end
