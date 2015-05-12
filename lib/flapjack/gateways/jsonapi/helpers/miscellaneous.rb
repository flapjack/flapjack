#!/usr/bin/env ruby

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Helpers
        module Miscellaneous

          def request_url
            rurl = request.url.split('?').first
            rurl << "?#{request.params.to_param}" unless request.params.empty?
            rurl
          end

          def wrapped_params(options = {})
            result = params['data']
            if result.nil?
              return([nil, false]) if options[:allow_nil].is_a?(TrueClass)
              logger.debug("No 'data' object found in the supplied JSON:")
              logger.debug(request.body.is_a?(StringIO) ? request.body.read : request.body)
              halt(err(403, "Data object must be provided"))
            end

            ext_bulk = !(request.content_type =~ /^(?:.+;)?\s*ext=bulk(?:\s*;\s*.+)?$/).nil?
            case result
            when Array
              halt(err(406, "JSONAPI Bulk Extension not set in headers")) unless ext_bulk
              [result, false]
            when Hash
              halt(err(406, "JSONAPI Bulk Extension was set in headers")) if ext_bulk
              [[result], true]
            else
              halt(err(403, "The received data object is not an Array or a Hash"))
            end
          end

          def wrapped_link_params(options = {})
            result = params['data']
            if result.nil?
              return([nil, false]) if !options[:singular].nil? && options[:allow_nil].is_a?(TrueClass)
              logger.debug("No 'data' object found in the following supplied JSON:")
              logger.debug(request.body.is_a?(StringIO) ? request.body.read : request.body)
              halt err(403, "No 'data' object received")
            end

            if !options[:multiple].nil?
              unless result.is_a?(Array) && result.all? {|r| options[:multiple][:data].jsonapi_type.eql?(r['type']) && !r['id'].nil? }

                halt(err(403, "Malformed data for multiple link endpoint"))
              end
              [result.map {|r| r[:id]}, false]
            elsif !options[:singular].nil?
              unless result.is_a?(Hash) && options[:singular][:data].jsonapi_type.eql?(result['type'])
                halt(err(403, "Malformed data for singular link endpoint"))
              end
              [[result[:id]], true]
            else
              halt(err(403, "Invalid endpoint definition")) # should never happen -- remove?
            end
          end

          def validate_data(data, options = {})
            valid_keys = ((options[:attributes] || []).map(&:to_s) + ['id', 'type', 'links'])
            sl = options[:singular_links] ? options[:singular_links].map(&:to_s) : []
            ml = options[:multiple_links] ? options[:multiple_links].map(&:to_s) : []
            all_links = sl + ml
            klass = options[:klass]

            data.each do |d|
              invalid_keys = d.keys - valid_keys
              halt(err(403, "Invalid attribute(s): #{invalid_keys.join(', ')}")) unless invalid_keys.empty?
              links = d['links']
              unless links.nil?
                halt(err(403, "Link(s) must be a Hash with String keys")) unless links.is_a?(Hash) &&
                  links.keys.all? {|k| k.is_a?(String)}
                invalid_links = links.keys - all_links
                halt(err(404, "Unknown link type(s): #{invalid_links.join(', ')}")) unless invalid_links.empty?
                links.each_pair do |k, v|
                  halt(err(403, "Link data for '#{k}' must be a Hash with String keys")) unless v.is_a?(Hash) && v.keys.all? {|vk| vk.is_a?(String)}
                  halt(err(403, "Link data for '#{k}' must have linkage references")) unless links[k].has_key?('linkage')

                  if sl.include?(k)
                    halt(err(403, "Linkage reference for '#{k}' must be a Hash with 'id' & 'type' String values")) unless links[k]['linkage'].is_a?(Hash) &&
                      v['linkage'].has_key?('id') &&
                      v['linkage'].has_key?('type') &&
                      v['linkage']['id'].is_a?(String) &&
                      v['linkage']['type'].is_a?(String)

                    unless is_link_type?(k, v['linkage']['type'], :klass => klass)
                      halt(err(403, "Linked '#{k}' has wrong type #{v['linkage']['type']}"))
                    end
                  else
                    halt(err(403, "Linkage reference for '#{k}' must be an Array of Hashes with 'id' & 'type' String values")) unless v['linkage'].is_a?(Array) &&
                      v['linkage'].all? {|l| l.has_key?('id') } &&
                      v['linkage'].all? {|l| l.has_key?('type') } &&
                      v['linkage'].all? {|l| l['id'].is_a?(String) } &&
                      v['linkage'].all? {|l| l['type'].is_a?(String) }

                    bad_type = v['linkage'].detect {|l| !is_link_type?(k, l['type'], :klass => klass)}
                    halt(err(403, "Linked '#{k}' has wrong type #{bad_type['type']}")) unless bad_type.nil?
                  end
                end
              end
            end
          end

          def is_link_type?(link_name, type, options = {})
            klass = options[:klass]
            klass_type = nil

            # SMELL mucking about with a zermelo protected method...
            klass.send(:with_association_data, link_name.to_sym) do |ad|
              klass_type = ad.data_klass.name.demodulize.underscore
            end

            type == klass_type
          end

          def jsonapi_type_for_link(klass, assoc_name)
            assoc_type = nil

            assocs = klass.respond_to?(:jsonapi_associations) ?
              klass.jsonapi_associations : {}

            singular = assocs[:singular] || []
            multiple = assocs[:multiple] || []

            als = (singular.select {|s| s.is_a?(Hash)} +
                   multiple.select {|m| m.is_a?(Hash)}).detect {|h| h.values.include?(assoc_name.to_sym) }

            assoc_alias = als.nil? ? nil : als.keys.first

            # SMELL mucking about with a zermelo protected method...
            klass.send(:with_association_data, (assoc_alias || assoc_name).to_sym) do |ad|
              assoc_type = ad.data_klass.name.demodulize.underscore
            end

            assoc_type
          end

          # NB: casts to UTC before converting to a timestamp
          def validate_and_parsetime(value)
            return unless value
            Time.iso8601(value).getutc
          rescue ArgumentError => e
            logger.error "Couldn't parse time from '#{value}'"
            nil
          end

        end
      end
    end
  end
end