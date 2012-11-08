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

    module Thin
      include Flapjack::Pikelet

      attr_accessor :port

      alias_method :orig_bootstrap, :bootstrap

      def bootstrap(opts = {})
        return if @bootstrapped

        if config = opts[:config]
          @port = config['port'] ? config['port'].to_i : nil
          @port = 3001 if (@port.nil? || @port <= 0 || @port > 65535)
        end

        orig_bootstrap(opts)
      end

    end

  end

end