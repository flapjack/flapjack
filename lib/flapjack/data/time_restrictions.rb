#!/usr/bin/env ruby

require 'set'

require 'ice_cube'

require 'zermelo/records/redis_record'

require 'flapjack/data/validators/id_validator'
require 'flapjack/data/route'

require 'flapjack/gateways/jsonapi/data/associations'

module Flapjack
  module Data
    class TimeRestrictions

      include Swagger::Blocks

      swagger_schema :TimeRestrictions do

      end

    end
  end
end

