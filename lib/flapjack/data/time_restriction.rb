#!/usr/bin/env ruby

require 'set'

require 'ice_cube'

require 'zermelo/records/redis'

require 'flapjack/data/extensions/short_name'
require 'flapjack/data/validators/id_validator'

require 'flapjack/data/route'

require 'flapjack/data/extensions/associations'

module Flapjack
  module Data
    class TimeRestriction

      include Swagger::Blocks

      include Flapjack::Data::Extensions::Associations
      include Flapjack::Data::Extensions::ShortName

      swagger_schema :TimeRestriction do

      end

    end
  end
end

