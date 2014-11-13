#!/usr/bin/env ruby

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Helpers
        module Resources

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

          def wrapped_params(name, options = {})
            result = params[name.to_s]
            if result.nil?
              if options[:error_on_nil].is_a?(FalseClass)
                result = [[{}], true]
              else
                logger.debug("No '#{name}' object found in the following supplied JSON:")
                logger.debug(request.body.is_a?(StringIO) ? request.body.read : request.body)
                halt err(403, "No '#{name}' object received")
              end
            end
            data, unwrap = case result
            when Array
              [result, false]
            when Hash
              [[result], true]
            else
              [nil, false]
            end
            halt(err(403, "The received '#{name}' object is not an Array or a Hash")) if data.nil?
            [data, unwrap]
          end

          def resource_post(klass, data, options = {})
            validate_data(data, options)

            resources    = nil

            data_ids = data.reject {|d| d['id'].nil? }.map {|dd| dd['id'].to_s }

            singular_links   = options[:singular_links]   || {}
            collection_links = options[:collection_links] || {}

            assoc_klasses = singular_links.values | collection_links.values

            klass.lock(*assoc_klasses) do
              conflicted_ids = klass.intersect(:id => data_ids).ids
              halt(err(403, "Resources already exist with the following ids: " +
                       conflicted_ids.join(', '))) unless conflicted_ids.empty?

              resources = data.each_with_object({}) do |rd, memo|
                r = klass.new( symbolize(rd.reject {|k| 'links'.eql?(k)}) )
                halt(err(403, "Validation failed, " + r.errors.full_messages.join(', '))) if r.invalid?
                memo[r] = rd['links']
              end

              # get linked objects, fail before save if we don't find them
              resource_links = resources.each_with_object({}) do |(r, links), memo|
                next if links.nil?

                singular_links.each_pair do |assoc, assoc_klass|
                  next unless links.has_key?(assoc)
                  memo[r.object_id] ||= {}
                  memo[r.object_id][assoc] = assoc_klass.find_by_id!(links[assoc])
                end

                collection_links.each_pair do |assoc, assoc_klass|
                  next unless links.has_key?(assoc)
                  memo[r.object_id] ||= {}
                  memo[r.object_id][assoc] = assoc_klass.find_by_ids!(*(links[assoc]))
                end
              end

              resources.keys.each do |r|
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
            end

            resources.keys
          end

          # TODO some of the link stuff could be done more efficiently -- check
          # for existence of ids rather than load the records outright

          def resource_put(klass, ids, data, options = {})
            validate_data(data, options)
            resources = klass.find_by_ids!(*ids)

            if data.map {|d| d['id'] }.sort != ids.sort
              halt err(403, "Id path/data mismatch")
            end

            resources_by_id = resources.each_with_object({}) {|r, o| o[r.id] = r }

            attrs            = options[:attributes] || []
            singular_links   = options[:singular_links]   || {}
            collection_links = options[:collection_links] || {}

            resource_links = data.each_with_object({}) do |d, memo|
              r = resources_by_id[d['id']]
              d.each_pair do |att, value|
                next unless attrs.include?(att)
                r.send("#{att}=".to_sym, value)
              end
              halt(err(403, "Validation failed, " + r.errors.full_messages.join(', '))) if r.invalid?
              next if d['links'].nil?

              singular_links.each_pair do |assoc, assoc_klass|
                next unless links.has_key?(assoc)
                memo[r.id] ||= {}
                memo[r.id][assoc] = assoc_klass.find_by_id!(links[assoc])
              end

              collection_links.each_pair do |assoc, assoc_klass|
                next unless links.has_key?(assoc)
                current_assoc_ids = r.send(assoc.to_sym).ids
                memo[r.id] ||= {}
                memo[r.id][assoc] = [
                  Flapjack::Data::Tag.find_by_ids!(links[assoc] - current_assoc_ids), # to_remove
                  Flapjack::Data::Tag.find_by_ids!(current_assoc_ids - links[assoc])  # to_add
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
                  elsif !v.is_a?(Array) && v.all? {|vv| vv.is_a?(String)}
                    halt(err(403, "Value for linked '#{k}' must be an Array of Strings"))
                  end
                end
              end
            end
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
        end
      end
    end
  end
end