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

          def wrapped_params(name, options = {})
            data_wrap = params['data']
            result = data_wrap.nil? ? nil : data_wrap[name.to_s]
            if result.nil?
              if options[:error_on_nil].is_a?(FalseClass)
                result = []
              else
                logger.debug("No '#{name}' object found in 'data' in the supplied JSON:")
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

          def wrapped_link_params(name, options = {})
            result = params['data']
            if result.nil?
              if options[:error_on_nil].is_a?(FalseClass)
                result = []
              else
                logger.debug("No 'data' object found in the following supplied JSON:")
                logger.debug(request.body.is_a?(StringIO) ? request.body.read : request.body)
                halt err(403, "No 'data' object received")
              end
            end

            if !options[:multiple].nil?
              unless result.is_a?(Array) && result.all? {|r| options[:multiple][:type].eql?(r['type']) && !r['id'].nil? }

                halt(err(403, "Malformed data for multiple link endpoint"))
              end
              [result.map {|r| r[:id]}, false]
            elsif !options[:singular].nil?
              unless result.is_a?(Hash) && options[:singular][:type].eql?(result['type'])
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
                halt(err(404, "Link(s) not found: #{invalid_links.join(', ')}")) unless invalid_links.empty?
                links.each_pair do |k, v|

                  if sl.include?(k)
                    unless v.nil?
                      if !v['id'].nil? && !v['type'].nil?
                        unless is_link_type?(k, v['type'], :klass => klass)
                          halt(err(403, "Linked '#{k}' has wrong type #{v['type']}"))
                        end

                        unless v['id'].is_a?(String)
                          halt(err(403, "Linked '#{k}' 'id' must be a String" ))
                        end
                      else
                        halt(err(403, "Linked '#{k}' must have 'id' and 'type' fields"))
                      end
                    end
                  elsif !v.is_a?(Hash)
                    halt(err(403, "Linked '#{k}' must be a Hash"))
                  # # Flapjack does not support heterogenous to_many types
                  # elsif !v['data'].nil?
                  #   if v['data'].is_a?(Array) && !v['data'].empty?
                  #     halt(err(403, "Linked '#{k}' 'data' Array objects must all have 'id' and 'type' fields")) unless v['data'].all? {|vv|
                  #       vv.has_key?('id') && vv['id'].is_a?(String) &&
                  #       vv.has_key?('type') && vv['type'].is_a?(String)
                  #     }

                  #     bad_type = v['data'].detect {|vv| !is_link_type?(k, vv['type'], :klass => klass)}

                  #     unless bad_type.nil?
                  #       halt(err(403, "Linked '#{k}' 'data' Array object has wrong type #{bad_type['type']}"))
                  #     end
                  #   else
                  #     halt(err(403, "Linked '#{k}' 'data' must be an Array"))
                  #   end
                  elsif !v['id'].nil? && !v['type'].nil?
                    unless is_link_type?(k, v['type'], :klass => klass)
                      halt(err(403, "Linked '#{k}' has wrong type #{v['type']}"))
                    end

                    unless v['id'].is_a?(Array) && v['id'].all? {|vv| vv.is_a?(String)}
                      halt(err(403, "Linked '#{k}' 'id' must be an Array of Strings"))
                    end
                  else
                    halt(err(403, "Linked '#{k}' must have 'id' and 'type' fields, or a 'data' Array"))
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

            singular = klass.respond_to?(:jsonapi_singular_associations) ?
              klass.jsonapi_singular_associations : []
            multiple = klass.respond_to?(:jsonapi_multiple_associations) ?
              klass.jsonapi_multiple_associations : []
            als = (singular.select {|s| s.is_a?(Hash)} +
                   multiple.select {|m| m.is_a?(Hash)}).detect {|h| h.values.include?(assoc_name.to_sym) }

            assoc_alias = als.nil? ? nil : als.keys.first

            # SMELL mucking about with a zermelo protected method...
            klass.send(:with_association_data, (assoc_alias || assoc_name).to_sym) do |ad|
              assoc_type = ad.data_klass.name.demodulize.underscore
            end

            assoc_type
          end

          def check_errors_on_save(record)
            return if record.save
            halt err(403, *record.errors.full_messages)
          end

          # NB: casts to UTC before converting to a timestamp
          def validate_and_parsetime(value)
            return unless value
            Time.iso8601(value).getutc.to_i
          rescue ArgumentError => e
            logger.error "Couldn't parse time from '#{value}'"
            nil
          end

        end
      end
    end
  end
end