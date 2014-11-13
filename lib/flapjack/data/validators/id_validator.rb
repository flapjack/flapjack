#!/usr/bin/env ruby

module Flapjack
  module Data
    module Validators
      class IdValidator < ActiveModel::Validator

        UUID_REGEXP = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

        def validate(record)
          if UUID_REGEXP.match(record.id.to_s).nil?
            record.errors.add('id', 'is not a UUID')
          end
        end
      end
    end
  end
end