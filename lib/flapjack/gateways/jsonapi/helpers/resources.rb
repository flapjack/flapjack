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
            record_data = data.reject {|k| 'links'.eql?(k)}
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

          def jsonapi_linkages(klass, resource_ids, opts = {})
            klass.jsonapi_association_links.each_with_object({}) do |(jl_name, jl_data), memo|
              memo[jl_name] = if opts[:resolve].nil? || !opts[:resolve].include?(jl_name.to_s)
                nil
              else
                data = if resource_ids.empty?
                  {}
                else
                  id_rel = klass.intersect(:id => resource_ids)
                  if jl_data.association_data.nil?
                    id_rel.all.each_with_object({}) {|r, memo|
                      memo[r.id] = r.send(jl_name.to_sym)
                    }
                  else
                    id_rel.associated_ids_for(jl_name)
                  end
                end
                LinkedData.new(:name => jl_name, :type => jl_data.type, :data => data)
              end
            end
          end

          def as_jsonapi(klass, jsonapi_type, resources_name, resources,
                         resource_ids, options = {})
            linked = nil

            incl   = options[:include] || []
            fields = options[:fields].nil? ? nil : options[:fields].map(&:to_sym)

            whitelist = if klass.respond_to?(:jsonapi_methods)
              (klass.jsonapi_methods[:get] || {}).attributes || []
            else
              []
            end

            whitelist |= [:id]

            jsonapi_fields = if fields.nil?
              whitelist
            else
              Set.new(fields).add(:id).keep_if {|f| whitelist.include?(f) }.to_a
            end

            links = jsonapi_linkages(klass, resource_ids, :resolve => incl)

            unless incl.empty?
              linked    = []
              ids_cache = {}
              included  = incl.collect {|i| i.split('.')}.sort_by(&:length)

              # TODO can this be replaced by the resources method param? --
              # resources is sometimes an array, replace those times so it's
              # always a scope
              retr_resources = klass.intersect(:id => resource_ids)

              included.each do |incl_clause|
                linked_data, _ = data_for_include_clause(ids_cache,
                  klass, retr_resources, [], incl_clause)
                case linked_data
                when Array
                  linked += linked_data
                when Hash
                  linked += [linked_data]
                end
              end
            end

            resources_as_json = resources.collect do |r|
              l = links.keys.each_with_object({}) do |v, memo|

                link_data = links[v]

                if link_data.nil?
                  memo[v] = "#{request.base_url}/#{resources_name}/#{r.id}/#{v}"
                else
                  memo[v] = {
                    :self    => "#{request.base_url}/#{resources_name}/#{r.id}/links/#{v}",
                    :related => "#{request.base_url}/#{resources_name}/#{r.id}/#{v}"
                  }

                  ids = link_data.data[r.id]
                  case ids
                  when Array, Set
                    memo[v].update(:linkage => ids.to_a.collect {|id| {:type => link_data.type, :id => id} })
                  when String
                    memo[v].update(:linkage => {:type => link_data.type, :id => ids})
                  end
                end
              end
              data = r.as_json(:only => jsonapi_fields).merge(
                :id    => r.id,
                :type  => jsonapi_type,
                :links => {:self => "#{request.base_url}/#{resources_name}/#{r.id}"}
              )
              data[:links].update(l) unless l.nil? || l.empty?
              data
            end

            if (resources_as_json.size == 1) && options[:unwrap].is_a?(TrueClass)
              resources_as_json = resources_as_json.first
            end

            [resources_as_json, linked]
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

            [dataset.page(page, :per_page => per_page).all,
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

          def data_for_include_clause(ids_cache, parent_klass, parent_resources, clause_done, clause_left)
            cl = clause_left.dup
            clause_fragment = cl.shift

            fragment_klass = nil

            # SMELL mucking about with a zermelo protected method...
            parent_klass.send(:with_association_data, clause_fragment.to_sym) do |data|
              fragment_klass = data.data_klass
            end

            return {} if fragment_klass.nil?

            clause_done.push(clause_fragment)

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

            if cl.size > 0
              data_for_include_clause(ids_cache, fragment_klass, fragment_resources,
                                      clause_done, cl)
            else
              # reached the end, ensure that data is stored as needed
              fragment_name = fragment_klass.name.demodulize.underscore.pluralize
              as_jsonapi(fragment_klass, fragment_klass.jsonapi_type,
                fragment_name, fragment_resources, fragment_ids, :unwrap => false)
            end
          end
        end
      end
    end
  end
end