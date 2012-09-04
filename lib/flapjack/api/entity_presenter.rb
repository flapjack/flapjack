#!/usr/bin/env ruby

require 'sinatra/base'

# require 'flapjack/data/entity'

module Flapjack

  class API < Sinatra::Base

    class EntityPresenter

      def initialise(entity, options = {})
        @entity = entity
        @redis = options[:redis]
      end

      # not sure if it's clean to be setting up another presenter here...
      def outages(start_time, end_time)
        {:checks => checks.collect {|c|

          entity_check = Flapjack::Data::EntityCheck.for_entity(entity,
            c, :redis => @redis)
          presenter = Flapjack::API::EntityCheckPresenter.new(entity_check)
          presenter.outages(start_time, end_time)

        }
      }
      end

      def unscheduled_maintenances(start_time, end_time)

      end

      def scheduled_maintenances(start_time, end_time)

      end

      def downtime(start_time, end_time)

      end

    private

      def checks
        @check_list ||= entity.check_list
      end

    end

  end

end