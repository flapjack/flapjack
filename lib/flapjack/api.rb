#!/usr/bin/env ruby

require 'flapjack/pikelet'

require 'flapjack/data/entity'
require 'flapjack/data/entity_check'

module Flapjack

  class API < Sinatra::Base

    extend Flapjack::Pikelet

    helpers do
      def json_status(code, reason)
        status code
        {
          :status => code,
          :reason => reason
        }.to_json
      end
    end

     def logger
      Flapjack::API.logger
    end

    before do
      # will only initialise the first time it's run
      Flapjack::API.bootstrap
    end

    # TODO Entity and EntityCheck should check for presence of Entity in Redis list

    def entity_status(entity_name)
      entity = Flapjack::Data::Entity.find_by_name(entity_name, :redis => @@redis)
      entity.check_list.sort.collect {|check|
        entity_check_status(entity, check)
      }
    end

    def entity_check_status(entity, check)
      entity_check = Flapjack::Data::EntityCheck.new(:entity_name => entity, :check => check,
        :redis => @@redis)
      return if entity_check.nil?
      { 'name'                                => c,
        'state'                               => entity_check.state,
        'in_unscheduled_maintenance'          => entity_check.in_unscheduled_maintenance?,
        'in_scheduled_maintenance'            => entity_check.in_scheduled_maintenance?,
        'last_update'                         => entity_check.last_update,
        'last_problem_notification'           => entity_check.last_problem_notification,
        'last_recovery_notification'          => entity_check.last_recovery_notification,
        'last_acknowledgement_notification'   => entity_check.last_acknowledgement_notification
      }
      # # possibly the below? need to discuss data spec
      # {'state'                       => entity_check.state,
      #  'last_update'                 => entity_check.last_update,
      #  'last_change'                 => entity_check.last_change,
      #  'summary'                     => entity_check.summary,
      #  'last_notifications'          => entity_check.last_notifications,
      #  'in_unscheduled_maintenance'  => entity_check.in_unscheduled_maintenance?,
      #  'in_scheduled_maintenance'    => entity_check.in_scheduled_maintenance?
      # }
    end

    get '/entities', :provides => :json do
      Flapjack::Data::Entity.all.collect {|e|
        entity_status(e)
      }
    end

    get '/entities/:entity/checks', :provides => :json do
      entity = Flapjack::Data::Entity.new(:entity => params[:entity],
        :redis => @@redis)
      entity.check_list
    end

    get '/entities/:entity/status', :provides => :json do
      entity_status(params[:entity])
    end

    get '/entities/:entity\::check', :provides => :json do
      entity_check_status(params[:entity], params[:check])
    end

    # list scheduled maintenance periods for a service on an entity
    get '/scheduled_maintenances/:entity\::check', :provides => :json do
      # TODO
    end

    # list unscheduled maintenance periods for a service on an entity
    get '/unscheduled_maintenances/:entity\::check', :provides => :json do
      # TODO
    end

    # create a scheduled maintenance period for a service on an entity
    post '/scheduled_maintenances/:entity\::check', :provides => :json do
      entity_check = Flapjack::Data::EntityCheck.new(:entity_name => params[:entity],
        :check => params[:check], :redis => @@redis)
      # TODO
    end

    # create an acknowledgement for a service on an entity
    post '/acknowledgements/:entity\::check', :provides => :json do
      entity_check = Flapjack::Data::EntityCheck.new(:entity_name => params[:entity],
        :check => params[:check], :redis => @@redis)
      entity_check.create_acknowledgement(params[:summary])
    end

    get "*" do
      status 404
    end

    put "*" do
      status 404
    end

    post "*" do
      status 404
    end

    delete "*" do
      status 404
    end

    not_found do
      json_status 404, "Not found"
    end

    error do
      json_status 500, env['sinatra.error'].message
    end

  end

end