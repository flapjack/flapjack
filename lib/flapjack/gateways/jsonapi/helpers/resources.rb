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

          def resource_post(klass, resources_name, options = {})
            resources_data, unwrap = wrapped_params

            singular_links, multiple_links = klass.association_klasses
            attributes = klass.respond_to?(:jsonapi_attributes) ?
              klass.jsonapi_attributes : []
            validate_data(resources_data, :attributes => attributes,
              :singular_links => singular_links.keys,
              :multiple_links => multiple_links.keys,
              :klass => klass)

            resources = nil

            id_field = klass.respond_to?(:jsonapi_id) ? klass.jsonapi_id : nil
            idf      = id_field || :id

            data_ids = resources_data.reject {|d| d[idf.to_s].nil? }.
                                      map    {|i| i[idf.to_s].to_s }

            assoc_klasses = singular_links.values.inject([]) {|memo, slv|
              memo << slv[:data]
              memo += slv[:related]
              memo
            } | multiple_links.values.inject([]) {|memo, mlv|
              memo << mlv[:data]
              memo += mlv[:related]
              memo
            }

            attribute_types = klass.attribute_types

            jsonapi_type = klass.jsonapi_type

            klass.lock(*assoc_klasses) do
              unless data_ids.empty?
                conflicted_ids = klass.intersect(idf => data_ids).ids
                halt(err(409, "#{klass.name.split('::').last.pluralize} already exist with the following #{idf}s: " +
                         conflicted_ids.join(', '))) unless conflicted_ids.empty?
              end
              links_by_resource = resources_data.each_with_object({}) do |rd, memo|
                record_data = normalise_json_data(attribute_types, rd)
                type = record_data.delete(:type)
                halt(err(409, "Resource missing data type")) if type.nil?
                halt(err(409, "Resource data type '#{type}' does not match endpoint '#{jsonapi_type}'")) unless jsonapi_type.eql?(type)
                record_data[:id] = record_data[id_field] unless id_field.nil?
                r = klass.new(record_data)
                halt(err(403, "Validation failed, " + r.errors.full_messages.join(', '))) if r.invalid?
                memo[r] = rd['links']
              end

              # get linked objects, fail before save if we don't find them
              resource_links = links_by_resource.each_with_object({}) do |(r, links), memo|
                next if links.nil?

                singular_links.each_pair do |assoc, assoc_klass|
                  next unless links.has_key?(assoc.to_s)
                  memo[r.object_id] ||= {}
                  memo[r.object_id][assoc.to_s] = assoc_klass[:data].find_by_id!(links[assoc.to_s]['linkage']['id'])
                end

                multiple_links.each_pair do |assoc, assoc_klass|
                  next unless links.has_key?(assoc.to_s)
                  memo[r.object_id] ||= {}
                  memo[r.object_id][assoc.to_s] = assoc_klass[:data].find_by_ids!(*(links[assoc.to_s]['linkage'].map {|l| l['id']}))
                end
              end

              links_by_resource.keys.each do |r|
                r.save
                rl = resource_links[r.object_id]
                next if rl.nil?
                rl.each_pair do |assoc, value|
                  case value
                  when Array
                    r.send(assoc.to_sym).add(*value)
                  else
                    r.send("#{assoc}=".to_sym, value)
                  end
                end
              end
              resources = links_by_resource.keys
            end

            resource_ids = resources.map(&:id)

            response.headers['Location'] = "#{request.base_url}/#{resources_name}/#{resource_ids.join(',')}"

            data, _ = as_jsonapi(klass, jsonapi_type, resources_name,
                                 resources, resource_ids,
                                 :unwrap => unwrap)

            Flapjack.dump_json(:data => data)
          end

          def resource_get(klass, resources_name, id, options = {})
            resources, links, meta = if id.nil?
              scoped = resource_filter_sort(klass,
               :filter => options[:filter], :sort => options[:sort])
              paginate_get(scoped, :page => params[:page],
                :per_page => params[:per_page])
            else
              [[klass.find_by_id!(id)], {}, {}]
            end

            links[:self] = request_url

            json_data = {:links => links}
            if resources.empty?
              json_data[:data] = []
            else

              fields = params[:fields].nil?  ? nil : params[:fields].split(',')
              incl   = params[:include].nil? ? nil : params[:include].split(',')
              data, included = as_jsonapi(klass, klass.jsonapi_type,
                                          resources_name, resources,
                                          (id.nil? ? resources.map(&:id) : [id]),
                                          :fields => fields, :include => incl,
                                          :unwrap => !id.nil?)

              json_data[:data] = data
              json_data[:included] = included unless included.nil? || included.empty?
              json_data[:meta] = meta unless meta.nil? || meta.empty?
            end
            Flapjack.dump_json(json_data)
          end

          def resource_patch(klass, resources_name, id, options = {})
            resources_data, unwrap = wrapped_params

            ids = resources_data.map {|d| d['id']}

            resources = if id.nil?
              resources = klass.find_by_ids!(*ids)
            else
              halt(err(403, "Id path/data mismatch")) unless ids.nil? || ids.eql?([id])
              [klass.find_by_id!(id)]
            end

            singular_links, multiple_links = klass.association_klasses
            attributes = klass.respond_to?(:jsonapi_attributes) ?
              klass.jsonapi_attributes : []
            validate_data(resources_data, :attributes => attributes,
              :singular_links => singular_links.keys,
              :multiple_links => multiple_links.keys,
              :klass => klass)

            resources_by_id = resources.each_with_object({}) {|r, o| o[r.id] = r }

            assoc_klasses = singular_links.values.each_with_object([]) {|slv, sl_memo|
              sl_memo << slv[:data]
              sl_memo += slv[:related] unless slv[:related].nil? || slv[:related].empty?
            } | multiple_links.values.each_with_object([]) {|mlv, ml_memo|
              ml_memo << mlv[:data]
              ml_memo += mlv[:related] unless mlv[:related].nil? || mlv[:related].empty?
            }

            jsonapi_type = klass.jsonapi_type

            attribute_types = klass.attribute_types

            resource_links = resources_data.each_with_object({}) do |d, memo|
              r = resources_by_id[d['id']]
              rd = normalise_json_data(attribute_types, d)

              type = rd.delete(:type)
              halt(err(409, "Resource missing data type")) if type.nil?
              halt(err(409, "Resource data type '#{type}' does not match endpoint '#{jsonapi_type}'")) unless jsonapi_type.eql?(type)

              rd.each_pair do |att, value|
                next unless attributes.include?(att.to_sym)
                r.send("#{att}=".to_sym, value)
              end
              halt(err(403, "Validation failed, " + r.errors.full_messages.join(', '))) if r.invalid?
              links = d['links']
              next if links.nil?

              singular_links.each_pair do |assoc, assoc_klass|
                next unless links.has_key?(assoc.to_s)
                memo[r.id] ||= {}
                memo[r.id][assoc.to_s] = assoc_klass[:data].find_by_id!(links[assoc.to_s]['linkage']['id'])
              end

              multiple_links.each_pair do |assoc, assoc_klass|
                next unless links.has_key?(assoc.to_s)
                current_assoc_ids = r.send(assoc.to_sym).ids
                memo[r.id] ||= {}

                link_ids = links[assoc.to_s]['linkage'].map {|l| l['id']}

                to_remove = current_assoc_ids - link_ids
                to_add    = link_ids - current_assoc_ids

                memo[r.id][assoc] = [
                  to_remove.empty? ? [] : assoc_klass[:data].find_by_ids!(*to_remove),
                  to_add.empty?    ? [] : assoc_klass[:data].find_by_ids!(*to_add)
                ]
              end
            end

            resources_by_id.each do |r_id, r|
              r.save
              rl = resource_links[r_id]
              next if rl.nil?
              rl.each_pair do |assoc, value|
                case value
                when Array
                  to_remove = value.first
                  to_add    = value.last

                  r.send(assoc.to_sym).delete(*to_remove) unless to_remove.empty?
                  r.send(assoc.to_sym).add(*to_add) unless to_add.empty?
                else
                  r.send("#{assoc}=".to_sym, value)
                end
              end
            end

            true
          end

          def resource_delete(klass, id)
            resources_data, unwrap = wrapped_params(:allow_nil => !id.nil?)

            ids = resources_data.nil? ? [id] : resources_data.map {|d| d['id']}

            if id.nil?
              resources = klass.intersect(:id => ids)
              halt(err(404, "Could not find all records to delete")) unless resources.count == ids.size
              resources.destroy_all
            else
              halt(err(403, "Id path/data mismatch")) unless ids.eql?([id])
              klass.find_by_id!(id).destroy
            end

            true
          end

          private

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
            singular = klass.respond_to?(:jsonapi_singular_associations) ?
              klass.jsonapi_singular_associations : []
            multiple = klass.respond_to?(:jsonapi_multiple_associations) ?
              klass.jsonapi_multiple_associations : []

            singular_aliases, singular_names = singular.partition {|s| s.is_a?(Hash)}
            multiple_aliases, multiple_names = multiple.partition {|m| m.is_a?(Hash)}

            links = (singular_names + multiple_names).each_with_object({}) do |n, memo|
              memo[n] = if !opts[:resolve].nil? && opts[:resolve].include?(n.to_s)
                data = resource_ids.empty? ? {} :
                  klass.intersect(:id => resource_ids).associated_ids_for(n)

                type = nil

                # SMELL mucking about with a zermelo protected method...
                klass.send(:with_association_data, n.to_sym) do |ad|
                  type = ad.data_klass.name.demodulize.underscore
                end

                LinkedData.new(:name => n, :type => type, :data => data)
              else
                nil
              end
            end

            aliases = [singular_aliases.inject({}, :merge),
                       multiple_aliases.inject({}, :merge)].inject(:merge)

            aliased_links = aliases.each_with_object({}) do |(n, a), memo|
              next if memo.has_key?(a)
              memo[a] = if !opts[:resolve].nil? && opts[:resolve].include?(a.to_s)

                data = resource_ids.empty? ? {} :
                  klass.intersect(:id => resource_ids).associated_ids_for(n)

                type = nil

                # SMELL mucking about with a zermelo protected method...
                klass.send(:with_association_data, n.to_sym) do |ad|
                  type = ad.data_klass.name.demodulize.underscore
                end

                LinkedData.new(:name => a, :type => type, :data => data)
              else
                nil
              end
            end

            links.update(aliased_links)
            links
          end

          def as_jsonapi(klass, jsonapi_type, resources_name, resources,
                         resource_ids, options = {})
            linked = nil

            incl   = options[:include] || []
            fields = options[:fields].nil? ? nil : options[:fields].map(&:to_sym)

            whitelist = (klass.respond_to?(:jsonapi_attributes) ?
              klass.jsonapi_attributes : []) | [:id]

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
            string_attrs = [:id] + (klass.respond_to?(:jsonapi_search_string_attributes) ?
              klass.jsonapi_search_string_attributes : [])

            boolean_attrs = klass.respond_to?(:jsonapi_search_boolean_attributes) ?
              klass.jsonapi_search_boolean_attributes : []

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