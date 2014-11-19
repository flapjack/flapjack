#!/usr/bin/env ruby

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Helpers
        module Miscellaneous

          def wrapped_params(name, options = {})
            result = params[name.to_s]
            if result.nil?
              if options[:error_on_nil].is_a?(FalseClass)
                result = []
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

          def wrapped_link_params(name, options = {})
            result = params[name.to_s]
            if result.nil?
              if options[:error_on_nil].is_a?(FalseClass)
                result = []
              else
                logger.debug("No '#{name}' object found in the following supplied JSON:")
                logger.debug(request.body.is_a?(StringIO) ? request.body.read : request.body)
                halt err(403, "No '#{name}' object received")
              end
            end
            data, unwrap = case result
            when Array
              [result, false]
            when String
              [[result], true]
            else
              [nil, false]
            end
            halt(err(403, "The received '#{name}' object is not an Array or a String")) if data.nil?
            [data, unwrap]
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