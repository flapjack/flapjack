#!/usr/bin/env ruby

# Formats entity data for presentation by the API methods in Flapjack::Gateways::API.
# Currently this just aggregates all of the check data for an entity, leaving
# clients to make any further calculations for themselves.

require 'sinatra/base'

require 'flapjack/gateways/api/entity_check_presenter'
require 'flapjack/data/entity_check'

module Flapjack

  module Gateways

    class API < Sinatra::Base

      class EntityPresenter

        def initialize(entity, options = {})
          @entity = entity
          @redis = options[:redis]
        end

        def status
          checks.collect {|c| check_presenter(c).status }
        end

        def outages(start_time, end_time)
          checks.collect {|c|
            {:check => c, :outages => check_presenter(c).outages(start_time, end_time)}
          }
        end

        def unscheduled_maintenance(start_time, end_time)
          checks.collect {|c|
            {:check => c, :unscheduled_maintenance =>
              check_presenter(c).unscheduled_maintenance(start_time, end_time)}
          }
        end

        def scheduled_maintenance(start_time, end_time)
          checks.collect {|c|
            {:check => c, :scheduled_maintenance =>
              check_presenter(c).scheduled_maintenance(start_time, end_time)}
          }
        end

        def downtime(start_time, end_time)
          checks.collect {|c|
            {:check => c, :downtime =>
              check_presenter(c).downtime(start_time, end_time)}
          }
        end

      private

        def checks
          @check_list ||= @entity.check_list.sort
        end

        def check_presenter(check)
          entity_check = Flapjack::Data::EntityCheck.for_entity(@entity, check,
            :redis => @redis)
          presenter = Flapjack::Gateways::API::EntityCheckPresenter.new(entity_check)
        end

      end

    end

  end

end