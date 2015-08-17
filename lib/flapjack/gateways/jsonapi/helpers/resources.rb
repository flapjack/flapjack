#!/usr/bin/env ruby

require 'active_support/inflector'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Helpers
        module Resources

          ISO8601_PAT = "(?:[1-9][0-9]*)?[0-9]{4}-" \
                        "(?:1[0-2]|0[1-9])-" \
                        "(?:3[0-1]|0[1-9]|[1-2][0-9])T" \
                        "(?:2[0-3]|[0-1][0-9]):" \
                        "[0-5][0-9]:[0-5][0-9](?:\\.[0-9]+)?" \
                        "(?:Z|[+-](?:2[0-3]|[0-1][0-9]):[0-5][0-9])?"

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

            klass.jsonapi_associations.each_with_object({}) do |(jl_name, jl_data), memo|
              next if jl_data.link.is_a?(FalseClass) && jl_data.includable.is_a?(FalseClass)

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
                    d = r.send(jl_name.to_sym)
                    memo[r.id] = case d
                    when nil
                      nil
                    when Zermelo::Filter, Zermelo::Associations::Multiple
                      d.ids
                    when Array, Set
                      d.map(&:id)
                    else
                      d.id
                    end
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

          def as_jsonapi_data(klass, resources_name, resources,
                              resource_ids, options = {})
            incl = options[:include]

            ids_cache = options[:ids_cache] || {}
            clause_done = options[:clause_done] || []

            fields = extract_fields(options[:fields], resources_name)

            whitelist = if klass.respond_to?(:jsonapi_methods)
              method_def = klass.jsonapi_methods[:get] || klass.jsonapi_methods[:post]
              method_def.nil? ? [] : method_def.attributes
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
              l = links.keys.inject({}) do |memo, k|

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
                memo
              end
              data = {
                :type => klass.short_model_name.singular,
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

          def locks_for_jsonapi_include(resource_class, options = {})
            incl = options[:include]
            clause_done = options[:clause_done] || []

            included = incl.collect {|i| i.split('.')}.sort_by(&:length)

            included.inject([]) do |memo, incl_clause|
              memo += lock_for_include_clause(resource_class, incl_clause,
                :clause_done => clause_done,
                :query_type => options[:query_type])
              memo
            end
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
                :ids_cache => ids_cache, :query_type => options[:query_type])
              memo
            end
          end

          def as_jsonapi(klass, resources_name, resources,
                         resource_ids, options = {})

            incl = options[:include]
            fields = options[:fields]

            ids_cache   = {}
            clause_done = []

            ret = {
              :data => as_jsonapi_data(klass, resources_name,
                resources, resource_ids, :fields => fields,
                :unwrap => options[:unwrap], :ids_cache => ids_cache,
                :clause_done => clause_done, :include => incl)
            }

            unless incl.nil? || incl.empty?
              ret[:included] = as_jsonapi_included(klass, resources_name, resources,
                :include => incl, :fields => fields, :ids_cache => ids_cache,
                :clause_done => clause_done, :query_type => options[:query_type])
            end

            ret
          end

          def parse_range_or_value(name, pattern, v, opts = {}, &block)
            rangeable = opts[:rangeable]

            if rangeable && (v =~ /\A(?:(#{pattern})\.\.(#{pattern})|(#{pattern})\.\.|\.\.(#{pattern}))\z/)
              start = nil
              start_s = $1 || $3
              unless start_s.nil?
                start = yield(start_s)
                halt(err(403, "Couldn't parse #{name} '#{start_s}'")) if start.nil?
              end

              finish = nil
              finish_s = $2 || $4
              unless finish_s.nil?
                finish = yield(finish_s)
                halt(err(403, "Couldn't parse #{name} '#{finish_s}'")) if finish.nil?
              end

              if !start.nil? && !finish.nil? && (start > finish)
                halt(err(403, "Range order cannot be inversed"))
              else
                Zermelo::Filters::IndexRange.new(start, finish, :by_score => true)
              end

            elsif v =~ /\A#{pattern}\z/
              t = yield(v)
              halt(err(403, "Couldn't parse #{name} '#{v}'")) if t.nil?
              t
            else
              halt(err(403, "Invalid #{name} parameter '#{v}'"))
            end
          end

          def filter_params(klass, filter)
            attributes = if klass.respond_to?(:jsonapi_methods)
              (klass.jsonapi_methods[:get] || {}).attributes || []
            else
              []
            end

            attribute_types = klass.attribute_types

            rangeable_attrs = []
            attrs_by_type = {}

            klass.send(:with_index_data) do |idx_data|
              idx_data.each do |k, d|
                next unless d.index_klass == ::Zermelo::Associations::RangeIndex
                rangeable_attrs << k
              end
            end

            Zermelo::ATTRIBUTE_TYPES.keys.each do |at|
              attrs_by_type[at] = attributes.select do |a|
                at.eql?(attribute_types[a])
              end
            end

            r = filter.each_with_object({}) do |filter_str, memo|
              k, v = filter_str.split(':', 2)
              halt(err(403, "Single filter parameters must be 'key:value'")) if k.nil? || v.nil?

              value = if attrs_by_type[:string].include?(k.to_sym) || :id.eql?(k.to_sym)
                if v =~ %r{^/(.+)/$}
                  Regexp.new($1)
                elsif v =~ /\|/
                  v.split('|')
                else
                  v
                end
              elsif attrs_by_type[:boolean].include?(k.to_sym)
                case v.downcase
                when '0', 'f', 'false', 'n', 'no'
                  false
                when '1', 't', 'true', 'y', 'yes'
                  true
                end

              elsif attrs_by_type[:timestamp].include?(k.to_sym)
                parse_range_or_value('timestamp', ISO8601_PAT, v, :rangeable => rangeable_attrs.include?(k.to_sym)) {|s|
                  begin; DateTime.parse(s); rescue ArgumentError; nil; end
                }
              elsif attrs_by_type[:integer].include?(k.to_sym)
                parse_range_or_value('integer', '\d+', v, :rangeable => rangeable_attrs.include?(k.to_sym)) {|s|
                  s.to_i
                }
              elsif attrs_by_type[:float].include?(k.to_sym)
                parse_range_or_value('float', '\d+(\.\d+)?', v, :rangeable => rangeable_attrs.include?(k.to_sym)) {|s|
                  s.to_f
                }
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

          def lock_for_include_clause(parent_klass, clause_left, options = {})
            clause_done = options[:clause_done]

            clause_fragment = clause_left.shift
            clause_done.push(clause_fragment)

            fragment_klass = nil

            parent_links = if parent_klass.respond_to?(:jsonapi_associations)
              parent_klass.jsonapi_associations || {}
            else
              {}
            end

            assoc_data = parent_links[clause_fragment.to_sym]

            # FIXME :includable apply to resource_*, :link apply to association_*
            return [] if assoc_data.nil? ||
              (:resource.eql?(options[:query_type]) && !assoc_data.includable) ||
              (:association.eql?(options[:query_type]) && !assoc_data.link)

            fragment_klass = assoc_data.data_klass

            data = [fragment_klass]

            return data if clause_left.empty?

            data + lock_for_include_clause(fragment_klass, clause_left,
              :clause_done => clause_done,
              :query_type => options[:query_type])
          end

          def data_for_include_clause(parent_klass, parent_resources,
            clause_left, options = {})

            clause_done = options[:clause_done]
            ids_cache   = options[:ids_cache]
            fields      = options[:fields]

            clause_fragment = clause_left.shift
            clause_done.push(clause_fragment)

            fragment_klass = nil

            parent_links = if parent_klass.respond_to?(:jsonapi_associations)
              parent_klass.jsonapi_associations || {}
            else
              {}
            end

            assoc_data = parent_links[clause_fragment.to_sym]

            # FIXME :includable apply to resource_*, :link apply to association_*
            return [] if assoc_data.nil? ||
              (:resource.eql?(options[:query_type]) && !assoc_data.includable) ||
              (:association.eql?(options[:query_type]) && !assoc_data.link)

            fragment_klass = assoc_data.data_klass

            ic_key = clause_done.join('.')

            ids_cache[ic_key] ||= if assoc_data.association_data.nil?
              parent_resources.all.each_with_object({}) {|r, memo|
                d = r.send(clause_fragment.to_sym)
                memo[r.id] = case d
                when nil
                  nil
                when Zermelo::Filter, Zermelo::Associations::Multiple
                  d.ids
                when Array, Set
                  d.map(&:id)
                else
                  d.id
                end
              }
            else
              parent_resources.associated_ids_for(clause_fragment.to_sym)
            end

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

            data = as_jsonapi_data(fragment_klass, fragment_name,
              fragment_resources, fragment_ids, :unwrap => false,
              :include => clause_left, :fields => fields,
              :clause_done => clause_done, :ids_cache => ids_cache)

            return data if clause_left.empty?

            linked = as_jsonapi_included(fragment_klass, fragment_name,
              fragment_resources, :include => clause_left, :fields => fields,
              :clause_done => clause_done, :ids_cache => ids_cache,
              :query_type => options[:query_type])

            data + linked
          end
        end
      end
    end
  end
end