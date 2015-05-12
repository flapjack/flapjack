#!/usr/bin/env ruby

require 'set'

require 'ice_cube'

require 'zermelo/records/redis'

require 'flapjack/data/validators/id_validator'
require 'flapjack/data/route'

require 'flapjack/gateways/jsonapi/data/associations'

module Flapjack
  module Data
    class TimeRestriction

      include Swagger::Blocks

      swagger_schema :TimeRestriction do

      end

    end
  end
end

