#!/usr/bin/env ruby

require 'active_support/inflector'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Helpers
        module Resources

          def resource_post(klass, resources_name, options = {})
            resources_data, unwrap = wrapped_params(resources_name)

            validate_data(resources_data, options)

            resources    = nil

            data_ids = resources_data.reject {|d| d['id'].nil? }.map {|dd| dd['id'].to_s }

            singular_links   = options[:singular_links]   || {}
            collection_links = options[:collection_links] || {}

            assoc_klasses = singular_links.values | collection_links.values

            klass.lock(*assoc_klasses) do
              conflicted_ids = klass.intersect(:id => data_ids).ids
              halt(err(403, "Resources already exist with the following ids: " +
                       conflicted_ids.join(', '))) unless conflicted_ids.empty?

              links_by_resource = resources_data.each_with_object({}) do |rd, memo|
                r = klass.new( symbolize(rd.reject {|k| 'links'.eql?(k)}) )
                halt(err(403, "Validation failed, " + r.errors.full_messages.join(', '))) if r.invalid?
                memo[r] = rd['links']
              end

              # get linked objects, fail before save if we don't find them
              resource_links = links_by_resource.each_with_object({}) do |(r, links), memo|
                next if links.nil?

                singular_links.each_pair do |assoc, assoc_klass|
                  next unless links.has_key?(assoc)
                  memo[r.object_id] ||= {}
                  memo[r.object_id][assoc] = assoc_klass.find_by_id!(links[assoc])
                end

                collection_links.each_pair do |assoc, assoc_klass|
                  next unless links.has_key?(assoc)
                  memo[r.object_id] ||= {}
                  memo[r.object_id][assoc] = assoc_klass.find_by_ids!(*links[assoc])
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

            response.headers['Location'] = "#{base_url}/#{resources_name}/#{resources.map(&:id).join(',')}"
            resources_as_json = klass.as_jsonapi(:unwrap => unwrap,
              :resources => resources, :ids => resources.map(&:id))
            Flapjack.dump_json(resources_name.to_sym => resources_as_json)
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

          def resource_get(klass, resources_name, ids, options = {})
            unwrap = !ids.nil? && (ids.size == 1)

            resources, meta = if ids
              requested = if (ids.size == 1)
                [klass.find_by_id!(*ids)]
              else
                resource_sort(klass, :sort => options[:sort]).find_by_ids!(*ids)
              end

              if requested.empty?
                raise Flapjack::Gateways::JSONAPI::RecordsNotFound.new(klass, ids)
              end

              [requested, {}]
            else
              paginate_get(resource_sort(klass, :sort => options[:sort]),
                :total => klass.count, :page => params[:page],
                :per_page => params[:per_page])
            end

            fields = params[:fields].nil?  ? nil : params[:fields].split(',')

            whitelist = (options[:attributes] || []) | ['id']

            jsonapi_fields = if fields.nil?
              whitelist.map(&:to_sym)
            else
              Set.new(fields).add(:id).keep_if {|f| whitelist.include?(f) }.to_a.map(&:to_sym)
            end

            linked = {}

            incl = params[:include].nil? ? nil : params[:include].split(',')

            unless incl.nil?
              ids_cache = {}
              included = incl.collect {|i| i.split('.')}.sort_by(&:length)
              included.each do |incl_clause|
                data_for_include_clause(linked, ids_cache, klass,
                  (ids || resources.map(&:id)), [], incl_clause)
              end
            end

            resources_as_json = klass.as_jsonapi(:resources => resources,
              :ids => (ids || resources.map(&:id)), :fields => jsonapi_fields,
              :unwrap => unwrap)

            data = {resources_name.to_sym => resources_as_json}

            unless linked.empty?
              data[:linked] = linked
            end

            Flapjack.dump_json(data.merge(meta))
          end

          def resource_put(klass, resources_name, ids, options = {})
            resources_data, _ = wrapped_params(resources_name)

            validate_data(resources_data, options)
            resources = klass.find_by_ids!(*ids)

            if resources_data.map {|d| d['id'] }.sort != ids.sort
              halt err(403, "Id path/data mismatch")
            end

            resources_by_id = resources.each_with_object({}) {|r, o| o[r.id] = r }

            attrs            = options[:attributes] || []
            singular_links   = options[:singular_links]   || {}
            collection_links = options[:collection_links] || {}

            resource_links = resources_data.each_with_object({}) do |d, memo|
              r = resources_by_id[d['id']]
              d.each_pair do |att, value|
                next unless attrs.include?(att)
                r.send("#{att}=".to_sym, value)
              end
              halt(err(403, "Validation failed, " + r.errors.full_messages.join(', '))) if r.invalid?
              links = d['links']
              next if links.nil?

              singular_links.each_pair do |assoc, assoc_klass|
                next unless links.has_key?(assoc)
                memo[r.id] ||= {}
                memo[r.id][assoc] = assoc_klass.find_by_id!(links[assoc])
              end

              collection_links.each_pair do |assoc, assoc_klass|
                next unless links.has_key?(assoc)
                current_assoc_ids = r.send(assoc.to_sym).ids
                memo[r.id] ||= {}

                to_remove = current_assoc_ids - links[assoc]
                to_add    = links[assoc] - current_assoc_ids

                memo[r.id][assoc] = [
                  to_remove.empty? ? [] : assoc_klass.find_by_ids!(*to_remove),
                  to_add.empty?    ? [] : assoc_klass.find_by_ids!(*to_add)
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
              raise Sandstorm::Records::Errors::RecordsNotFound.new(klass, missing_ids)
            end

            resources.destroy_all
            true
          end

          private

          def validate_data(data, options = {})
            valid_keys = ((options[:attributes] || []) + ['links']) | ['id']
            cl = options[:collection_links] ? options[:collection_links].keys : []
            sl = options[:singular_links]   ? options[:singular_links].keys   : []
            all_links = cl + sl

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
               :meta => {
                 :pagination => {
                   :page        => page,
                   :per_page    => per_page,
                   :total_pages => total_pages,
                   :total_count => total,
                 }
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

          def data_for_include_clause(linked, ids_cache, parent_klass, parent_ids, clause_done, clause_left)
            clause_fragment = clause_left.shift

            fragment_klass = nil

            # SMELL mucking about with a sandstorm protected method...
            parent_klass.send(:with_association_data, clause_fragment.to_sym) do |data|
              fragment_klass = data.data_klass
            end

            return if fragment_klass.nil?

            clause_done.push(clause_fragment)

            unless ids_cache.has_key?(clause_done)
              ids_cache[clause_done] = parent_klass.intersect(:id => parent_ids).
                associated_ids_for(clause_fragment.to_sym)
            end

            fragment_ids_by_parent_id = ids_cache[clause_done]

            # TODO currently only handles to_many (unwrap false),
            # needs to handle to_one (unwrap true)
            fragment_ids = fragment_ids_by_parent_id.values.flatten

            if clause_left.size > 0
              data_for_include_clause(linked, ids_cache, fragment_klass, fragment_ids,
                                      clause_done, clause_left)
            else
              # reached the end, ensure that data is stored as needed
              fragment_resources = fragment_klass.find_by_ids!(*fragment_ids)
              linked[fragment_klass.name.split('::').last.downcase.pluralize] =
                fragment_klass.as_jsonapi(:resources => fragment_resources,
                  :ids => fragment_ids, :unwrap => false)
            end
          end
        end
      end
    end
  end
end