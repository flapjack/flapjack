#!/usr/bin/env ruby

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Helpers
        module Miscellaneous

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