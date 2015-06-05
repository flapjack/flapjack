#!/usr/bin/env ruby

require 'active_support/inflector'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Helpers
        module Resources

          class LinkedData
            attr_accessor :name, :type, :data

            def initialize(attrs = {})
              [:name, :type, :data].each do |att|
                instance_variable_set("@#{att}", attrs[att])
              end
            end
          end

          # TODO refactor some of these methods into a module, included in data/ classes

          def normalise_json_data(attribute_types, data)
            record_data = data.dup
            attribute_types.each_pair do |name, type|
              t = record_data[name.to_s]
              next unless t.is_a?(String) && :timestamp.eql?(type)
              begin
                record_data[name.to_s] = DateTime.parse(t)
              rescue ArgumentError
                record_data[name.to_s] = nil
              end
            end
            symbolize(record_data)
          end

          def jsonapi_linkages(klass, resources, resource_ids, opts = {})
            clause_done = opts[:clause_done]
            ids_cache = opts[:ids_cache]

            klass.jsonapi_association_links.each_with_object({}) do |(jl_name, jl_data), memo|

              memo[jl_name] = if opts[:resolve].nil?
                nil
              elsif !opts[:resolve].any? {|i|
                i.split('.', 2).first.eql?(jl_name.to_s)
              }

                nil
              else
                data = if resource_ids.empty?
                  {}
                elsif jl_data.association_data.nil?
                  resources.all.each_with_object({}) {|r, memo|
                    memo[r.id] = r.send(jl_name.to_sym)
                  }
                else
                  ic_key = (clause_done + [jl_name.to_s]).join('.')
                  ids_cache[ic_key] ||=
                    resources.associated_ids_for(jl_name)
                  ids_cache[ic_key]
                end
                LinkedData.new(:name => jl_name, :type => jl_data.type, :data => data)
              end
            end
          end

          def extract_fields(fields, resources_name)
            return if fields.nil?
            raise "Field limits must be passed as a Hash" unless fields.is_a?(Hash)
            return unless fields.has_key?(resources_name)
            fields[resources_name].split(',').map(&:to_sym)
          end

          # NB resources must be a Zermelo filter scope, not an array of Zermelo records

          def as_jsonapi_data(klass, jsonapi_type, resources_name, resources,
                              resource_ids, options = {})

            incl = options[:include]

            ids_cache = options[:ids_cache] || {}
            clause_done = options[:clause_done] || []

            fields = extract_fields(options[:fields], resources_name)

            whitelist = if klass.respond_to?(:jsonapi_methods)
              (klass.jsonapi_methods[:get] || {}).attributes || []
            else
              []
            end

            jsonapi_fields = if fields.nil?
              whitelist
            else
              Set.new(fields).keep_if {|f| whitelist.include?(f) }.to_a
            end

            links = jsonapi_linkages(klass, resources, resource_ids,
              :ids_cache => ids_cache, :clause_done => clause_done, :resolve => incl)

            resources_as_json = resources.collect do |r|
              r_id = r.id
              l = links.keys.each_with_object({}) do |k, memo|

                link_data = links[k]

                memo[k] = {
                  :links => {
                    :self    => "#{request.base_url}/#{resources_name}/#{r_id}/relationships/#{k}",
                    :related => "#{request.base_url}/#{resources_name}/#{r_id}/#{k}"
                  }
                }

                unless link_data.nil?
                  ids = link_data.data[r_id]
                  case ids
                  when Array, Set
                    memo[k].update(:data => ids.to_a.collect {|id| {:type => link_data.type, :id => id} })
                  when String
                    memo[k].update(:data => {:type => link_data.type, :id => ids})
                  end
                end
              end
              data = {
                :type => jsonapi_type,
                :id => r_id
              }
              attrs = r.as_json(:only => jsonapi_fields)
              data[:attributes] = attrs unless attrs.empty?
              data[:relationships] = l unless l.nil? || l.empty?
              data
            end

            unless (resources_as_json.size == 1) && options[:unwrap].is_a?(TrueClass)
              return resources_as_json
            end

            resources_as_json.first
          end

          def as_jsonapi_included(klass, resources_name, resources, options = {})
            incl = options[:include]
            raise "No data to include" if incl.nil? || incl.empty?

            ids_cache = options[:ids_cache] || {}
            clause_done = options[:clause_done] || []

            fields = options[:fields]

            included = incl.collect {|i| i.split('.')}.sort_by(&:length)

            included.inject([]) do |memo, incl_clause|
              memo += data_for_include_clause(klass, resources,
                incl_clause, :fields => fields, :clause_done => clause_done,
                :ids_cache => ids_cache)
              memo
            end
          end

          def as_jsonapi(klass, jsonapi_type, resources_name, resources,
                         resource_ids, options = {})

            incl = options[:include]
            fields = options[:fields]

            ids_cache   = {}
            clause_done = []

            ret = {
              :data => as_jsonapi_data(klass, jsonapi_type, resources_name,
                resources, resource_ids, :fields => fields,
                :unwrap => options[:unwrap], :ids_cache => ids_cache,
                :clause_done => clause_done, :include => incl)
            }

            unless incl.nil? || incl.empty?
              ret[:included] = as_jsonapi_included(klass, resources_name, resources,
                :include => incl, :fields => fields, :ids_cache => ids_cache,
                :clause_done => clause_done)
            end

            ret
          end

          def filter_params(klass, filter)
            attributes = if klass.respond_to?(:jsonapi_methods)
              (klass.jsonapi_methods[:get] || {}).attributes || []
            else
              []
            end

            attribute_types = klass.attribute_types

            string_attrs = [:id] + (attributes.select {|a|
              :string.eql?(attribute_types[a])
            })

            boolean_attrs = attributes.select {|a|
              :boolean.eql?(attribute_types[a])
            }

            r = filter.each_with_object({}) do |filter_str, memo|
              k, v = filter_str.split(':', 2)
              halt(err(403, "Single filter parameters must be 'key:value'")) if k.nil? || v.nil?

              value = if string_attrs.include?(k.to_sym)
                if v =~ %r{^/(.+)/$}
                  Regexp.new($1)
                elsif v =~ /\|/
                  v.split('|')
                else
                  v
                end
              elsif boolean_attrs.include?(k.to_sym)
                case v.downcase
                when '0', 'f', 'false', 'n', 'no'
                  false
                when '1', 't', 'true', 'y', 'yes'
                  true
                end
              end

              halt(err(403, "Invalid filter key '#{k}'")) if value.nil?
              memo[k.to_sym] = value
            end
          end

          def resource_filter_sort(klass, options = {})
            options[:sort] ||= 'id'
            scope = klass

            unless params[:filter].nil?
              unless params[:filter].is_a?(Array)
                halt(err(403, "Filter parameters must be passed as an Array"))
              end
              filter_ops = filter_params(klass, params[:filter])
              scope = scope.intersect(filter_ops)
            end

            sort_opts = if params[:sort].nil?
              options[:sort].to_sym
            else
              sort_params = params[:sort].split(',')

              if sort_params.any? {|sp| sp !~ /^(?:\+|-)/ }
                halt(err(403, "Sort parameters must start with +/-"))
              end

              sort_params.each_with_object({}) do |sort_param, memo|
                sort_param =~ /^(\+|\-)([a-z_]+)$/i
                rev  = $1
                term = $2
                memo[term.to_sym] = (rev == '-') ? :desc : :asc
              end
            end

            scope = scope.sort(sort_opts)
            scope
          end

          def paginate_get(dataset, options = {})
            return([[], {}, {}]) if dataset.nil?

            total = dataset.count
            return([[], {}, {}]) if total == 0

            page = options[:page].to_i
            page = (page > 0) ? page : 1

            per_page = options[:per_page].to_i
            per_page = (per_page > 0) ? per_page : 20

            total_pages = (total.to_f / per_page).ceil

            pages = set_page_numbers(page, total_pages)
            links = create_links(pages)
            headers['Link']        = create_link_header(links) unless links.empty?
            headers['Total-Count'] = total_pages.to_s

            [dataset.page(page, :per_page => per_page),
              links,
              {
                :pagination => {
                  :page        => page,
                  :per_page    => per_page,
                  :total_pages => total_pages,
                  :total_count => total
                }
              }
            ]
          end

          def set_page_numbers(page, total_pages)
            pages = {}
            pages[:first] = 1 # if (total_pages > 1) && (page > 1)
            pages[:prev]  = page - 1 if (page > 1)
            pages[:next]  = page + 1 if page < total_pages
            pages[:last]  = total_pages # if (total_pages > 1) && (page < total_pages)
            pages
          end

          def create_links(pages)
            url_without_params = request.url.split('?').first
            per_page = params[:per_page] # ? params[:per_page].to_i : 20

            links = {}
            pages.each do |key, value|
              page_params = {'page' => value }
              page_params.update('per_page' => per_page) unless per_page.nil?
              new_params = request.params.merge(page_params)
              links[key] = "#{url_without_params}?#{new_params.to_query}"
            end
            links
          end

          def create_link_header(links)
            links.collect {|(k, v)| "<#{v}; rel=\"#{k}\"" }.join(', ')
          end

          def data_for_include_clause(parent_klass, parent_resources,
            clause_left, options = {})

            clause_done = options[:clause_done]
            ids_cache   = options[:ids_cache]
            fields      = options[:fields]

            clause_fragment = clause_left.shift
            clause_done.push(clause_fragment)

            fragment_klass = nil

            # SMELL mucking about with a zermelo protected method...
            parent_klass.send(:with_association_data, clause_fragment.to_sym) do |data|
              fragment_klass = data.data_klass
            end

            return [] if fragment_klass.nil?

            ic_key = clause_done.join('.')

            ids_cache[ic_key] ||=
              parent_resources.associated_ids_for(clause_fragment.to_sym)

            # to_many associations have array values, to_one associations have string ids
            fragment_ids = ids_cache[ic_key].values.inject([]) do |memo, v|
              memo += case v
              when Array
                v
              when Set
                v.to_a
              else
                [v]
              end
              memo
            end
            return [] if fragment_ids.empty?

            fragment_resources = fragment_klass.intersect(:id => fragment_ids)
            fragment_name = fragment_klass.name.demodulize.underscore.pluralize

            data = as_jsonapi_data(fragment_klass, fragment_klass.jsonapi_type,
              fragment_name, fragment_resources, fragment_ids, :unwrap => false,
              :include => clause_left, :fields => fields,
              :clause_done => clause_done, :ids_cache => ids_cache)

            return data if clause_left.empty?

            linked = as_jsonapi_included(fragment_klass, fragment_name,
              fragment_resources, :include => clause_left, :fields => fields,
              :clause_done => clause_done, :ids_cache => ids_cache)

            data + linked
          end
        end
      end
    end
  end
end