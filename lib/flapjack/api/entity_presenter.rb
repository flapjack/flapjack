#!/usr/bin/env ruby

# Formats entity data for presentation by the API methods in Flapjack::API.
# Currently this just aggregates all of the check data for an entity, leaving
# clients to make any further calculations for themselves.

require 'sinatra/base'

require 'flapjack/api/entity_check_presenter'
require 'flapjack/data/entity_check'

module Flapjack

  class API < Sinatra::Base

    class EntityPresenter

      def initialise(entity, options = {})
        @entity = entity
        @redis = options[:redis]
      end

      def outages(start_time, end_time)
        checks.collect {|c|
          {:check => c, :outages => check_presenter(c).outages(start_time, end_time)}
        }
      end

      def unscheduled_maintenances(start_time, end_time)
        checks.collect {|c|
          {:check => c, :unscheduled_maintenances =>
            check_presenter(c).unscheduled_maintenances(start_time, end_time)}
        }
      end

      def scheduled_maintenances(start_time, end_time)
        checks.collect {|c|
          {:check => c, :scheduled_maintenances =>
            check_presenter(c).scheduled_maintenances(start_time, end_time)}
        }
      end

      def downtime(start_time, end_time)
        checks.collect {|c|
          {:check => c, :scheduled_maintenances =>
            check_presenter(c).downtime(start_time, end_time)}
        }
      end

    private

      def checks
        @check_list ||= entity.check_list
      end

      def check_presenter(check)
        entity_check = Flapjack::Data::EntityCheck.for_entity(@entity, c,
          :redis => @redis)
        presenter = Flapjack::API::EntityCheckPresenter.new(entity_check)
      end

    end

  end

end