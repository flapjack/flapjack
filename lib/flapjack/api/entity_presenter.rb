#!/usr/bin/env ruby

require 'sinatra/base'

# require 'flapjack/data/entity'

module Flapjack

  class API < Sinatra::Base

    class EntityPresenter

      def initialise(entity)
        @entity = entity
      end

    end

  end

end