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

              jsonapi_links = resource_class.jsonapi_association_links || {}

              singular_links = jsonapi_links.select {|n, jd|
                :singular.eql?(jd.number)
              }

              multiple_links = jsonapi_links.select {|n, jd|
                :multiple.eql?(jd.number)
              }

              assocs = singular_links.empty? ? nil : singular_links.keys.map(&:to_s).join('|')
              multi_assocs = multiple_links.empty? ? nil: multiple_links.keys.map(&:to_s).join('|')

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
                    link_type = link_data.type
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

                    swagger_path "/#{resource}/{#{single}_id}/relationships/#{link_name}" do
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
                    link_type = link_data.type
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
                    swagger_path "/#{resource}/{#{single}_id}/relationships/#{link_name}" do
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

                  fields = params[:fields]
                  incl   = params[:include].nil? ? nil : params[:include].split(',')

                  status 200

                  assoc = jsonapi_links[assoc_name.to_sym]

                  halt(err(404, 'Unknown association')) if assoc.nil?

                  empty = false
                  included = nil
                  result = nil
                  meta = nil

                  resource_class.lock(*assoc.lock_klasses) do
                    res = resource_class.intersect(:id => resource_id)
                    empty = res.empty?

                    unless empty
                      associated = res.all.first.send(assoc_name.to_sym)

                      result = case assoc.number
                      when :multiple

                        unless params[:filter].nil?
                          unless params[:filter].is_a?(Array)
                            halt(err(403, "Filter parameters must be passed as an Array"))
                          end

                          unless params[:filter].all? {|f| f = /^#{assocs}\.([^,]+))*$/ }
                            halt(err(403, "Filter params must start with '#{assocs}.': '#{params[:sort]}'"))
                          end

                          filters = params[:filter].collect do |f|
                            f.sub(/^#{assocs}\./, '')
                          end

                          filter_ops = filter_params(assoc.data_klass, filters)
                          associated = associated.intersect(filter_ops)
                        end

                        if params[:sort].nil?
                          associated = associated.sort(:id => :asc)
                        elsif params[:sort] =~ /^(?:\+|\-)#{assocs}\.(?:[^,]+)(?:,(?:\+|\-)#{assocs}\.[^,]+)*$/
                          sort_params = params[:sort].sub(/^#{assocs}\./, '').gsub(/,#{assocs}\./, ',').split(',')

                          if sort_params.any? {|sp| sp !~ /^(?:\+|-)/ }
                            halt(err(403, "Sort parameters must start with +/- '#{params[:sort]}'"))
                          end

                          sort_params.each_with_object({}) do |sort_param, memo|
                            sort_param =~ /^(\+|\-)([a-z_]+)$/i
                            rev  = $1
                            term = $2
                            memo[term.to_sym] = (rev == '-') ? :desc : :asc
                          end

                          associated = associated.sort(sort_params)
                        else
                          halt(err(403, "Sort params must start with '(+/-)#{assocs}.': '#{params[:sort]}'"))
                        end

                        resources, _, meta = paginate_get(associated, :page => params[:page],
                          :per_page => params[:per_page])

                        result = resources.eql?([]) ? [] : resources.ids
                      when :singular
                        result = associated.id
                      end

                      unless incl.nil?
                        included = as_jsonapi_included(resource_class, resource, res,
                          :include => incl, :fields => fields)
                      end
                    end
                  end
                  raise ::Zermelo::Records::Errors::RecordNotFound.new(resource_class, resource_id) if empty

                  links = {
                    :self    => "#{request.base_url}/#{resource}/#{resource_id}/relationships/#{assoc_name}",
                    :related => "#{request.base_url}/#{resource}/#{resource_id}/#{assoc_name}"
                  }

                  data = case result
                  when Array
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
end
