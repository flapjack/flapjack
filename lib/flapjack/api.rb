#!/usr/bin/env ruby

require 'flapjack/pikelet'

require 'flapjack/data/entity'
require 'flapjack/data/entity_check'

# We can always move this to a Sinatra::Base subclass if the Grape
# functionality isn't worth the extra gems needed

module Flapjack

  class API < Grape::API

    extend Flapjack::Pikelet

    # clients can pass Accept header for XML, JSON, Atom, RSS, and text
    # if none of these is specified, we prefer JSON
    default_format :json
    error_format :json

    version 'v1', :using => :header, :vendor => 'flapjack'

    helpers do
      def persistence
        ::Flapjack::API.bootstrap(:redis => {:driver => :ruby})
        ::Flapjack::API.persistence
      end

      def logger
        ::Flapjack::API.bootstrap(:redis => {:driver => :ruby})
        ::Flapjack::API.logger
      end
    end

    get 'entities' do
      # entities = Flapjack::Data::Entity.all
    end

    get 'entities/:entity/checks' do
      entity = Flapjack::Data::Entity.new(:entity => params[:entity],
        :redis => persistence)
      entity.check_list
    end

    get 'entities/:entity/statuses' do
      entity = Flapjack::Data::Entity.new(:entity => params[:entity],
        :redis => persistence)
      entity.check_list.sort.collect do |c|
        entity_check = Flapjack::Data::EntityCheck.new(:entity => params[:entity], :check => c,
          :redis => persistence)
        { 'name'                                => c,
          'state'                               => entity_check.state,
          'in_unscheduled_maintenance'          => entity_check.in_unscheduled_maintenance?,
          'in_scheduled_maintenance'            => entity_check.in_scheduled_maintenance?,
          'last_update'                         => entity_check.last_update,
          'last_problem_notification'           => entity_check.last_problem_notification,
          'last_recovery_notification'          => entity_check.last_recovery_notification,
          'last_acknowledgement_notification'   => entity_check.last_acknowledgement_notification }
      end
    end

    get 'entity_checks/:entity\::check' do
      entity_check = Flapjack::Data::EntityCheck.new(:entity => params[:entity],
        :check => params[:check], :redis => persistence)
      {:state                       => entity_check.state,
       :last_update                 => entity_check.last_update,
       :last_change                 => entity_check.last_change,
       :summary                     => entity_check.summary,
       :last_notifications          => entity_check.last_notifications,
       :in_unscheduled_maintenance  => entity_check.in_unscheduled_maintenance?,
       :in_scheduled_maintenance    => entity_check.in_scheduled_maintenance?
      }
    end

    post 'acknowledgements/:entity\::check' do
      entity_check = Flapjack::Data::EntityCheck.new(:entity => params[:entity],
        :check => params[:check], :redis => persistence)
      entity_check.create_acknowledgement(params[:summary])
    end

    post 'scheduled_maintenances/:entity\::check' do
      entity_check = Flapjack::Data::EntityCheck.new(:entity => params[:entity],
        :check => params[:check], :redis => persistence)
    end

  end

end