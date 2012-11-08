#!/usr/bin/env ruby

require 'flapjack/pikelet'

module Flapjack
  module Gateways

    module Generic
      include Flapjack::GenericPikelet
    end

    module Resque
      include Flapjack::Pikelet
    end

  end

end