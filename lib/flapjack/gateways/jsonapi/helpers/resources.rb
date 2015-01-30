#!/usr/bin/env ruby

require 'active_support/inflector'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Helpers
        module Resources

          def resource_post(klass, resources_name, options = {})
            resources_data, unwrap = wrapped_params(resources_name)

            attributes = klass.respond_to?(:jsonapi_attributes) ?
              klass.jsonapi_attributes : []
            singular_links, multiple_links = association_klasses(klass)

            validate_data(resources_data, :attributes => attributes,
              :singular_links => singular_links.keys,
              :multiple_links => multiple_links.keys)

            resources = nil

            id_field = klass.respond_to?(:jsonapi_id) ? klass.jsonapi_id : nil
            idf      = id_field || :id

            data_ids = resources_data.reject {|d| d[idf.to_s].nil? }.
                                      map    {|i| i[idf.to_s].to_s }

            assoc_klasses = singular_links.values.inject([]) {|sl_memo, slv|
              sl_memo << slv[:data]
              sl_memo slv[:related] unless (slv[:related].nil? || slv[:related].empty?)
              sl_memo
            } | multiple_links.values.inject([]) {|ml_memo, mlv|
              ml_memo << mlv[:data]
              ml_memo += mlv[:related] unless (mlv[:related].nil? || mlv[:related].empty?)
              ml_memo
            }

            attribute_types = klass.attribute_types

            klass.lock(*assoc_klasses) do
              unless data_ids.empty?
                conflicted_ids = klass.intersect(idf => data_ids).ids
                halt(err(403, "#{klass.name.split('::').last.pluralize} already exist with the following #{idf}s: " +
                         conflicted_ids.join(', '))) unless conflicted_ids.empty?
              end
              links_by_resource = resources_data.each_with_object({}) do |rd, memo|
                record_data = normalise_json_data(attribute_types, rd)
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
                  memo[r.object_id][assoc.to_s] = assoc_klass[:data].find_by_id!(links[assoc.to_s])
                end

                multiple_links.each_pair do |assoc, assoc_klass|
                  next unless links.has_key?(assoc.to_s)
                  memo[r.object_id] ||= {}
                  memo[r.object_id][assoc.to_s] = assoc_klass[:data].find_by_ids!(*links[assoc.to_s])
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

            response.headers['Location'] = "#{request.base_url}/#{resources_name}/#{resources.map(&:id).join(',')}"

            data, links_out, linked = as_jsonapi(klass, resources_name,
                                                 resources,
                                                 resources.map(&:id),
                                                 :unwrap => unwrap)

            json_data = {}
            json_data.update(:links => links_out) unless links_out.nil? || links_out.empty?
            json_data.update(resources_name.to_sym => data)
            json_data.update(:linked => linked) unless linked.nil? || linked.empty?
            Flapjack.dump_json(json_data)
          end

          def resource_get(klass, resources_name, ids, options = {})
            unwrap = !ids.nil? && (ids.size == 1)

            sort_scope = proc { resource_sort(klass, :sort => options[:sort]) }

            resources, meta = if ids
              requested = if (ids.size == 1)
                [klass.find_by_id!(*ids)]
              else
                sort_scope.call.find_by_ids!(*ids)
              end

              if requested.empty?
                raise Flapjack::Gateways::JSONAPI::RecordsNotFound.new(klass, ids)
              end

              [requested, nil]
            else
              paginate_get(sort_scope.call,
                :total => klass.count, :page => params[:page],
                :per_page => params[:per_page])
            end

            fields = params[:fields].nil?  ? nil : params[:fields].split(',')
            incl   = params[:include].nil? ? nil : params[:include].split(',')
            data, links_out, linked = as_jsonapi(klass, resources_name, resources,
                                      (ids || resources.map(&:id)),
                                      :fields => fields, :include => incl,
                                      :unwrap => unwrap)

            json_data = {}
            json_data.update(:links => links_out) unless links_out.nil? || links_out.empty?
            json_data.update(resources_name.to_sym => data)
            json_data.update(:linked => linked) unless linked.nil? || linked.empty?
            json_data.update(:meta => meta) unless meta.nil? || meta.empty?
            Flapjack.dump_json(json_data)
          end

          def resource_put(klass, resources_name, ids, options = {})
            resources_data, _ = wrapped_params(resources_name)
            singular_links, multiple_links = association_klasses(klass)
            attributes = klass.respond_to?(:jsonapi_attributes) ?
              klass.jsonapi_attributes : []
            validate_data(resources_data, :attributes => attributes,
              :singular_links => singular_links.keys,
              :multiple_links => multiple_links.keys)
            resources = klass.find_by_ids!(*ids)

            if resources_data.map {|d| d['id'] }.sort != ids.sort
              halt err(403, "Id path/data mismatch")
            end

            resources_by_id = resources.each_with_object({}) {|r, o| o[r.id] = r }

            assoc_klasses = singular_links.values.each_with_object([]) {|slv, sl_memo|
              sl_memo << slv[:data]
              sl_memo += slv[:related] unless slv[:related].nil? || slv[:related].empty?
            } | multiple_links.values.each_with_object([]) {|mlv, ml_memo|
              ml_memo << mlv[:data]
              ml_memo += mlv[:related] unless mlv[:related].nil? || mlv[:related].empty?
            }

            attribute_types = klass.attribute_types

            resource_links = resources_data.each_with_object({}) do |d, memo|
              r = resources_by_id[d['id']]
              normalise_json_data(attribute_types, d).each_pair do |att, value|
                next unless attributes.include?(att.to_sym)
                r.send("#{att}=".to_sym, value)
              end
              halt(err(403, "Validation failed, " + r.errors.full_messages.join(', '))) if r.invalid?
              links = d['links']
              next if links.nil?

              singular_links.each_pair do |assoc, assoc_klass|
                next unless links.has_key?(assoc.to_s)
                memo[r.id] ||= {}
                memo[r.id][assoc] = assoc_klass[:data].find_by_id!(links[assoc])
              end

              multiple_links.each_pair do |assoc, assoc_klass|
                next unless links.has_key?(assoc.to_s)
                current_assoc_ids = r.send(assoc.to_sym).ids
                memo[r.id] ||= {}

                to_remove = current_assoc_ids - links[assoc.to_s]
                to_add    = links[assoc.to_s] - current_assoc_ids

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

          def resource_delete(klass, ids)
            resources = klass.intersect(:id => ids)
            missing_ids = ids - resources.ids

            unless missing_ids.empty?
              raise Zermelo::Records::Errors::RecordsNotFound.new(klass, missing_ids)
            end

            resources.destroy_all
            true
          end

          private

          def association_klasses(klass)
            singular = klass.respond_to?(:jsonapi_singular_associations) ?
              klass.jsonapi_singular_associations : []
            multiple = klass.respond_to?(:jsonapi_multiple_associations) ?
              klass.jsonapi_multiple_associations : []

            singular_aliases, singular_names = singular.partition {|s| s.is_a?(Hash)}
            multiple_aliases, multiple_names = multiple.partition {|m| m.is_a?(Hash)}

            singular_links = {}
            multiple_links = {}

            # SMELL mucking about with a zermelo protected method...
            klass.send(:with_association_data) do |assoc_data|
              assoc_data.each_pair do |name, data|
                if sa = singular_aliases.detect {|a| a.has_key?(name) }
                  singular_links[sa[name]] = {:data => data.data_klass, :related => data.related_klasses}
                elsif singular_names.include?(name)
                  singular_links[name] = {:data => data.data_klass, :related => data.related_klasses}
                elsif ma = multiple_aliases.detect {|a| a.has_key?(name) }
                  multiple_links[ma[name]] = {:data => data.data_klass, :related => data.related_klasses}
                elsif multiple_names.include?(name)
                  multiple_links[name] = {:data => data.data_klass, :related => data.related_klasses}
                end
              end
            end

            [singular_links, multiple_links]
          end

          def jsonapi_linkages(klass, resource_ids)
            singular = klass.respond_to?(:jsonapi_singular_associations) ?
              klass.jsonapi_singular_associations : []
            multiple = klass.respond_to?(:jsonapi_multiple_associations) ?
              klass.jsonapi_multiple_associations : []

            singular_aliases, singular_names = singular.partition {|s| s.is_a?(Hash)}
            multiple_aliases, multiple_names = multiple.partition {|m| m.is_a?(Hash)}

            links = (singular_names + multiple_names).each_with_object({}) do |n, memo|
              memo[n] = resource_ids.empty? ? {} :
                klass.intersect(:id => resource_ids).associated_ids_for(n)
            end

            aliases = [singular_aliases.inject({}, :merge),
                       multiple_aliases.inject({}, :merge)].inject(:merge)

            aliased_links = aliases.each_with_object({}) do |(n, a), memo|
              next if memo.has_key?(a)
              memo[a] = resource_ids.empty? ? {} :
                klass.intersect(:id => resource_ids).associated_ids_for(n)
            end

            links.update(aliased_links)
            links
          end

          def as_jsonapi(klass, resources_name, resources, resource_ids, options = {})
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

            links_out = {}

            links = jsonapi_linkages(klass, resource_ids)

            links.each_pair do |k, v|
              next unless v.any? {|id, vv| vv.is_a?(String) || (vv.is_a?(Array) && !vv.empty?) }
              lo_name = "#{resources_name}.#{k}"
              links_out[lo_name] = "#{request.base_url}/#{k.to_s.pluralize}/{#{lo_name}}"
            end

            unless incl.empty?
              linked    = {}
              ids_cache = {}
              included  = incl.collect {|i| i.split('.')}.sort_by(&:length)
              included.each do |incl_clause|
                linked_data, links_data = data_for_include_clause(ids_cache,
                  klass, resource_ids, [], incl_clause)
                linked.update(linked_data)
                links_out.update(links_data) unless links_data.nil? || links_data.empty?
              end
            end

            resources_as_json = resources.collect do |r|
              l = links.keys.each_with_object({}) do |v, memo|
                vs = links[v][r.id]
                memo[v] = vs.is_a?(Set) ? vs.to_a : vs
              end
              r.as_json(:only => jsonapi_fields).merge(:links => l)
            end

            if (resources_as_json.size == 1) && options[:unwrap].is_a?(TrueClass)
              resources_as_json = resources_as_json.first
            end

            [resources_as_json, links_out, linked]
          end

          def resource_sort(klass, options = {})
            sort_opts = if params[:sort].nil?
              options[:sort].to_sym || :id
            else
              params[:sort].split(',').each_with_object({}) do |sort_param|
                sort_param =~ /^(-)?([a-z_]+)/i
                rev  = $1
                term = $2
                memo[term.to_sym] = rev.nil? ? :asc : :desc
              end
            end

            klass.sort(sort_opts)
          end

          def validate_data(data, options = {})
            valid_keys = ((options[:attributes] || []).map(&:to_s) + ['links']) | ['id']
            sl = options[:singular_links] ? options[:singular_links].map(&:to_s) : []
            ml = options[:multiple_links] ? options[:multiple_links].map(&:to_s) : []
            all_links = sl + ml

            data.each do |d|
              invalid_keys = d.keys - valid_keys
              halt(err(403, "Invalid attribute(s): #{invalid_keys.join(', ')}")) unless invalid_keys.empty?
              links = d['links']
              unless links.nil?
                halt(err(403, "Link(s) must be a Hash with String keys")) unless links.is_a?(Hash) &&
                  links.keys.all? {|k| k.is_a?(String)}
                invalid_links = links.keys - all_links
                halt(err(403, "Invalid link(s): #{invalid_links.join(', ')}")) unless invalid_links.empty?
                links.each_pair do |k, v|
                  if sl.include?(k)
                    halt(err(403, "Value for linked '#{k}' must be a String")) unless v.is_a?(String)
                  elsif !v.is_a?(Array) || v.any? {|vv| !vv.is_a?(String)}
                    halt(err(403, "Value for linked '#{k}' must be an Array of Strings"))
                  end
                end
              end
            end
          end

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

          def paginate_get(dataset, options = {})
            return([[], {}]) if dataset.nil?

            page = options[:page].to_i
            page = (page > 0) ? page : 1

            per_page = options[:per_page].to_i
            per_page = (per_page > 0) ? per_page : 20

            total = options[:total].to_i
            total = (total < 0) ? 0 : total

            total_pages = (total.to_f / per_page).ceil

            pages = set_page_numbers(page, total_pages)
            links = create_links(pages)
            headers['Link']        = links.join(', ') unless links.empty?
            headers['Total-Count'] = total_pages.to_s

            [dataset.page(page, :per_page => per_page),
             {
               :pagination => {
                 :page        => page,
                 :per_page    => per_page,
                 :total_pages => total_pages,
                 :total_count => total,
               }
             }
            ]
          end

          def set_page_numbers(page, total_pages)
            pages = {}
            pages[:first] = 1 if (total_pages > 1) && (page > 1)
            pages[:prev]  = page - 1 if (page > 1)
            pages[:next]  = page + 1 if page < total_pages
            pages[:last]  = total_pages if (total_pages > 1) && (page < total_pages)
            pages
          end

          def create_links(pages)
            url_without_params = request.url.split('?').first
            per_page = params[:per_page] ? params[:per_page].to_i : 20

            links = []
            pages.each do |key, value|
              new_params = request.query_parameters.merge({ page: value, per_page: per_page })
              links << "<#{url_without_params}?#{new_params.to_param}>; rel=\"#{key}\""
            end
            links
          end

          def data_for_include_clause(ids_cache, parent_klass, parent_ids, clause_done, clause_left)
            clause_fragment = clause_left.shift

            fragment_klass = nil

            # SMELL mucking about with a zermelo protected method...
            parent_klass.send(:with_association_data, clause_fragment.to_sym) do |data|
              fragment_klass = data.data_klass
            end

            return {} if fragment_klass.nil?

            clause_done.push(clause_fragment)

            ic_key = clause_done.join('.')

            unless ids_cache.has_key?(ic_key)
              ids_cache[ic_key] = parent_klass.intersect(:id => parent_ids).
                associated_ids_for(clause_fragment.to_sym)
            end

            fragment_ids_by_parent_id = ids_cache[ic_key]

            # to_many associations have array values, to_one associations have string ids
            fragment_ids = fragment_ids_by_parent_id.values.inject([]) do |memo, v|
              memo += (v.is_a?(Array) ? v : [v])
              memo
            end

            if clause_left.size > 0
              data_for_include_clause(ids_cache, fragment_klass, fragment_ids,
                                      clause_done, clause_left)
            else
              # reached the end, ensure that data is stored as needed
              fragment_name = fragment_klass.name.split('::').last.downcase.pluralize
              fragment_resources = fragment_klass.find_by_ids!(*fragment_ids)
              fragment_json, fragment_links, _ = as_jsonapi(fragment_klass,
                fragment_name, fragment_resources, fragment_ids,
                :unwrap => false)
              [{fragment_name.to_sym => fragment_json}, fragment_links]
            end
          end
        end
      end
    end
  end
end