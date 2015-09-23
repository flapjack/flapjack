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

            assoc = options[:association]
            number = assoc.number

            if result.nil?
              return([nil, false]) if :singular.eql?(number) && options[:allow_nil].is_a?(TrueClass)
              logger.debug("No 'data' object found in the following supplied JSON:")
              logger.debug(request.body.is_a?(StringIO) ? request.body.read : request.body)
              halt err(403, "No 'data' object received")
            end

            case number
            when :multiple
              unless result.is_a?(Array) && result.all? {|r| assoc.type.eql?(r['type']) && !r['id'].nil? }
                halt(err(403, "Malformed data for multiple link endpoint"))
              end
              [result.map {|r| r[:id]}, false]
            when :singular
              unless result.is_a?(Hash) && assoc.type.eql?(result['type'])
                halt(err(403, "Malformed data for singular link endpoint"))
              end
              [[result[:id]], true]
            else
              halt(err(403, "Invalid endpoint definition"))
            end
          end

          def validate_data(data, options = {})
            valid_keys = ['id', 'type', 'attributes', 'relationships']
            valid_attrs = (options[:attributes] || []).map(&:to_s)
            sl = options[:singular_links] ? options[:singular_links].keys.map(&:to_s) : []
            ml = options[:multiple_links] ? options[:multiple_links].keys.map(&:to_s) : []
            all_links = sl + ml

            # FIXME check error codes against JSONAPI spec

            data.each do |d|
              invalid_keys = d.keys - valid_keys
              halt(err(403, "Invalid key(s): #{invalid_keys.join(', ')}")) unless invalid_keys.empty?
              if d.has_key?('attributes')
                attrs = d['attributes']
                halt(err(403, "Attributes must be a Hash with String keys")) unless attrs.is_a?(Hash) &&
                  attrs.keys.all? {|k| k.is_a?(String)}
                invalid_attrs = attrs.keys - valid_attrs
                halt(err(403, "Invalid attribute(s): #{invalid_attrs.join(', ')}")) unless invalid_attrs.empty?
              end
              if d.has_key?('relationships')
                links = d['relationships']
                halt(err(403, "Relationships(s) must be a Hash with String keys")) unless links.is_a?(Hash) &&
                  links.keys.all? {|k| k.is_a?(String)}
                invalid_links = links.keys - all_links
                halt(err(404, "Unknown relationship type(s): #{invalid_links.join(', ')}")) unless invalid_links.empty?
                links.each_pair do |k, v|
                  halt(err(403, "Related data for '#{k}' must be a Hash with String keys")) unless v.is_a?(Hash) && v.keys.all? {|vk| vk.is_a?(String)}
                  halt(err(403, "Related data for '#{k}' must have data references")) unless links[k].has_key?('data')

                  if sl.include?(k)
                    halt(err(403, "Data reference for '#{k}' must be a Hash with 'id' & 'type' String values")) unless links[k]['data'].is_a?(Hash) &&
                      v['data'].has_key?('id') &&
                      v['data'].has_key?('type') &&
                      v['data']['id'].is_a?(String) &&
                      v['data']['type'].is_a?(String)

                    unless options[:singular_links][k.to_sym].type == v['data']['type']
                      halt(err(403, "Related '#{k}' has wrong type #{v['data']['type']}"))
                    end
                  else
                    halt(err(403, "Data reference for '#{k}' must be an Array of Hashes with 'id' & 'type' String values")) unless v['data'].is_a?(Array) &&
                      v['data'].all? {|l| l.has_key?('id') } &&
                      v['data'].all? {|l| l.has_key?('type') } &&
                      v['data'].all? {|l| l['id'].is_a?(String) } &&
                      v['data'].all? {|l| l['type'].is_a?(String) }

                    t = options[:multiple_links][k.to_sym].type
                    bad_type = v['data'].detect {|l| !t.eql?(l['type'])}
                    unless bad_type.nil?
                      halt(403, "Data reference for '#{k}' has invalid type '#{bad_type}', should be '#{t}")
                    end
                  end
                end
              end
            end
          end

          def validate_and_parsetime(value)
            return unless value
            Time.iso8601(value).getutc
          rescue ArgumentError
            logger.error "Couldn't parse time from '#{value}'"
            nil
          end

        end
      end
    end
  end
end