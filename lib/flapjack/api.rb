#!/usr/bin/env ruby

require 'flapjack/pikelet'

require 'flapjack/models/entity'
require 'flapjack/models/entity_check'

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

    get 'entities/:entity/checks' do
      entity = Flapjack::Data::Entity.new(:entity => params[:entity],
        :redis => persistence)
      entity.check_list
    end

    get 'entity_checks/:entity\::check' do
      entity_check = Flapjack::Data::EntityCheck.new(:entity => params[:entity],
        :check => params[:check], :redis => persistence)
      entity_check.status
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