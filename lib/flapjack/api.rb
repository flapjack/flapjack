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

    def entity_status(entity_name)
      entity = Flapjack::Data::Entity.find_by_name(entity_name, :redis => @@redis)
      return if entity.nil?
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
    end

    get '/entities', :provides => :json do
      Flapjack::Data::Entity.all.sort {|ent| ent.id }.collect {|e|
        entity_status(e)
      }
    end

    get '/checks/:entity', :provides => :json do
      entity = Flapjack::Data::Entity.find_by_name(params[:entity],
        :redis => @@redis)
      if entity.nil?
        status 404
        return
      end
      entity.check_list
    end

    get '/status/:entity', :provides => :json do
      sta = entity_status(params[:entity])
      if sta.nil?
        status 404
        return
      end
      sta
    end

    get '/status/:entity/:check', :provides => :json do
      sta = entity_check_status(params[:entity], params[:check])
      if sta.nil?
        status 404
        return
      end
      sta
    end

    # list scheduled maintenance periods for a service on an entity
    get '/scheduled_maintenances/:entity/:check', :provides => :json do
      entity = Flapjack::Data::Entity.find_by_name(params[:entity],
        :redis => @@redis)
      if entity.nil?
        status 404
        return
      end      
      entity_check = Flapjack::Data::EntityCheck.new(:entity => entity,
        :check => params[:check], :redis => @@redis)
      entity_check.scheduled_maintenances
    end

    # list unscheduled maintenance periods for a service on an entity
    get '/unscheduled_maintenances/:entity/:check', :provides => :json do
      entity = Flapjack::Data::Entity.find_by_name(params[:entity],
        :redis => @@redis)
      if entity.nil?
        status 404
        return
      end 
      entity_check = Flapjack::Data::EntityCheck.new(:entity => entity,
        :check => params[:check], :redis => @@redis)
      entity_check.unscheduled_maintenances
    end

    # create a scheduled maintenance period for a service on an entity
    post '/scheduled_maintenances/:entity/:check', :provides => :json do
      entity = Flapjack::Data::Entity.find_by_name(params[:entity],
        :redis => @@redis)
      if entity.nil?
        status 404
        return
      end       
      entity_check = Flapjack::Data::EntityCheck.new(:entity => entity,
        :check => params[:check], :redis => @@redis)
      entity_check.create_scheduled_maintenance(:start_time => params[:start_time],
        :duration => params[:duration], :summary => params[:summary])
    end

    # create an acknowledgement for a service on an entity
    post '/acknowledgements/:entity/:check', :provides => :json do
      entity = Flapjack::Data::Entity.find_by_name(params[:entity], 
        :redis => @@redis)
      if entity.nil?
        status 404
        return
      end       
      entity_check = Flapjack::Data::EntityCheck.new(:entity => entity,
        :check => params[:check], :redis => @@redis)
      entity_check.create_acknowledgement(params[:summary])
    end

    # get "*" do
    #   status 404
    # end

    # put "*" do
    #   status 404
    # end

    # post "*" do
    #   status 404
    # end

    # delete "*" do
    #   status 404
    # end

    not_found do
      json_status 404, "Not found"
    end

    error do
      json_status 500, env['sinatra.error'].message
    end

  end

end