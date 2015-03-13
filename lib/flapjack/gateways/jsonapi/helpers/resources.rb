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
            resources_data, unwrap = wrapped_params(resources_name)

            attributes = klass.respond_to?(:jsonapi_attributes) ?
              klass.jsonapi_attributes : []

            validate_data(resources_data, :attributes => attributes, :klass => klass)

            resources = nil

            id_field = klass.respond_to?(:jsonapi_id) ? klass.jsonapi_id : nil
            idf      = id_field || :id

            data_ids = resources_data.reject {|d| d[idf.to_s].nil? }.
                                      map    {|i| i[idf.to_s].to_s }

            attribute_types = klass.attribute_types

            jsonapi_type = klass.jsonapi_type

            klass.lock do
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

              resources = links_by_resource.keys
              resources.each {|r| r.save }
            end

            resource_ids = resources.map(&:id)

            response.headers['Location'] = "#{request.base_url}/#{resources_name}/#{resource_ids.join(',')}"

            data, _ = as_jsonapi(klass, jsonapi_type, resources_name,
                                 resources, resource_ids,
                                 :unwrap => unwrap)

            Flapjack.dump_json(:data => {resources_name.to_sym => data})
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
            data, included = as_jsonapi(klass, klass.jsonapi_type,
                                        resources_name, resources,
                                        (ids || resources.map(&:id)),
                                        :fields => fields, :include => incl,
                                        :unwrap => unwrap)

            json_data = {}
            json_data.update(resources_name.to_sym => data)

            # TODO pagination links move from meta to top-level "links"

            # TODO top-level links, add "self" => URL

            output = {:data => json_data}
            output.update(:included => included) unless included.nil? || included.empty?
            output.update(:meta => meta) unless meta.nil? || meta.empty?
            Flapjack.dump_json(output)
          end

          def resource_patch(klass, resources_name, ids, options = {})
            resources_data, _ = wrapped_params(resources_name)
            singular_links, multiple_links = klass.association_klasses
            attributes = klass.respond_to?(:jsonapi_attributes) ?
              klass.jsonapi_attributes : []
            validate_data(resources_data, :attributes => attributes,
              :singular_links => singular_links.keys,
              :multiple_links => multiple_links.keys,
              :klass => klass)
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

            jsonapi_type = klass.jsonapi_type

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
                memo[r.id][assoc.to_s] = assoc_klass[:data].find_by_id!(links[assoc.to_s]['id'])
              end

              multiple_links.each_pair do |assoc, assoc_klass|
                next unless links.has_key?(assoc.to_s)
                current_assoc_ids = r.send(assoc.to_sym).ids
                memo[r.id] ||= {}

                link_ids = links[assoc.to_s]['id']

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

              # TODO can this be replaced by the resources method param?
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
                    :related => "#{request.base_url}/#{resources_name}/#{r.id}/#{v}",
                    :type    => link_data.type,
                  }

                  ids = link_data.data[r.id]
                  case ids
                  when Array
                    memo[v].update(:ids => ids)
                  when String
                    memo[v].update(:id => ids)
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

            [dataset.page(page, :per_page => per_page).all,
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