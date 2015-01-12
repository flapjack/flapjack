#!/usr/bin/env ruby

require 'flapjack'

module Flapjack
  module Data
    module Validators
      class IdValidator < ActiveModel::Validator

        UUID_REGEXP = /^#{Flapjack::UUID_RE}$/

        def validate(record)
          if !record.id.nil? && UUID_REGEXP.match(record.id.to_s).nil?
            record.errors.add(:id, 'is not a UUID')
          end
        end
      end
    end
  end
end