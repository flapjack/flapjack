#!/usr/bin/env ruby

# Formats entity data for presentation by the API methods in Flapjack::Gateways::API.
# Currently this just aggregates all of the check data for an entity, leaving
# clients to make any further calculations for themselves.

require 'sinatra/base'

require 'flapjack/gateways/jsonapi/check_presenter'
require 'flapjack/data/check'

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      class EntityPresenter

        def initialize(entity, options = {})
          @entity = entity
        end

        def status
          checks.collect {|c| {:entity => @entity.name, :check => c.name,
                               :status => check_presenter(c).status } }
        end

        def outages(start_time, end_time)
          checks.collect {|c|
            {:entity => @entity.name, :check => c.name, :outages => check_presenter(c).outages(start_time, end_time)}
          }
        end

        def unscheduled_maintenances(start_time, end_time)
          checks.collect {|c|
            {:entity => @entity.name, :check => c.name, :unscheduled_maintenances =>
              check_presenter(c).unscheduled_maintenances(start_time, end_time)}
          }
        end

        def scheduled_maintenances(start_time, end_time)
          checks.collect {|c|
            {:entity => @entity.name, :check => c.name, :scheduled_maintenances =>
              check_presenter(c).scheduled_maintenances(start_time, end_time)}
          }
        end

        def downtime(start_time, end_time)
          checks.collect {|c|
            {:entity => @entity.name, :check => c.name, :downtime =>
              check_presenter(c).downtime(start_time, end_time)}
          }
        end

      private

        def checks
          @checks ||= @entity.checks.all.sort_by(&:name)
        end

        def check_presenter(check)
          return if check.nil?
          presenter = Flapjack::Gateways::JSONAPI::CheckPresenter.new(check)
        end


      end

    end

  end

end
