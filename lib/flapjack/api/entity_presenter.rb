#!/usr/bin/env ruby

require 'sinatra/base'

# require 'flapjack/data/entity'

module Flapjack

  class API < Sinatra::Base

    class EntityPresenter

      def initialise(entity)
        @entity = entity
      end

      def outages(start_time, end_time)

      end

      def unscheduled_maintenances(start_time, end_time)

      end

      def scheduled_maintenances(start_time, end_time)

      end

      def downtime(start_time, end_time)

      end

    end

  end

end