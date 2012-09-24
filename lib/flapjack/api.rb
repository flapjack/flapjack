#!/usr/bin/env ruby

# A HTTP-based API server, which provides queries to determine the status of
# entities and the checks that are reported against them.
#
# There's a matching flapjack-diner gem which consumes data from this API
# (currently at https://github.com/ali-graham/flapjack-diner -- this will change.)

require 'time'

require 'rack/fiber_pool'
require 'sinatra/base'

require 'flapjack/pikelet'

require 'flapjack/api/entity_presenter'

require 'flapjack/data/entity'
require 'flapjack/data/entity_check'

module Flapjack

  class API < Sinatra::Base

    # doesn't work with Rack::Test for some reason
    unless 'test'.eql?(FLAPJACK_ENV)
      rescue_exception = Proc.new { |env, exception|
        logger.error exception.message
        logger.error exception.backtrace.join("\n")
        [503, {}, {:status => 503, :reason => exception.message}.to_json]
      }

      use Rack::FiberPool, :size => 25, :rescue_exception => rescue_exception
    end
    use Rack::MethodOverride
    extend Flapjack::Pikelet

    before do
      # will only initialise the first time it's run
      Flapjack::API.bootstrap
    end

    get '/entities' do
      content_type :json
      ret = Flapjack::Data::Entity.all(:redis => @@redis).sort_by(&:name).collect {|e|
        {'id' => e.id, 'name' => e.name,
         'checks' => e.check_list.sort.collect {|c|
                       entity_check_status(e, c)
                     }
        }
      }
      ret.to_json
    end

    get '/checks/:entity' do
      content_type :json
      entity = Flapjack::Data::Entity.find_by_name(params[:entity], :redis => @@redis)
      if entity.nil?
        status 404
        return
      end
      entity.check_list.to_json
    end

    get %r{/status/([a-zA-Z0-9][a-zA-Z0-9\.\-]*[a-zA-Z0-9])(?:/(\w+))?} do
      content_type :json

      entity_name = params[:captures][0]
      check = params[:captures][1]

      entity = Flapjack::Data::Entity.find_by_name(entity_name, :redis => @@redis)
      if entity.nil?
        status 404
        return
      end

      ret = if check
        entity_check_status(entity, check)
      else
        entity.check_list.sort.collect {|c|
          entity_check_status(entity, c)
        }
      end
      ret.to_json
    end

    # the first capture group in the regex checks for acceptable
    # characters in a domain name -- this will also match strings
    # that aren't acceptable domain names as well, of course.
    get %r{/outages/([a-zA-Z0-9][a-zA-Z0-9\.\-]*[a-zA-Z0-9])(?:/(\w+))?} do
      content_type :json

      entity_name = params[:captures][0]
      check = params[:captures][1]

      entity = entity = Flapjack::Data::Entity.find_by_name(entity_name, :redis => @@redis)
      if entity.nil?
        status 404
        return
      end

      start_time = validate_and_parsetime(params[:start_time])
      end_time   = validate_and_parsetime(params[:end_time])

      presenter = if check
        entity_check = Flapjack::Data::EntityCheck.for_entity(entity,
          check, :redis => @@redis)
        Flapjack::API::EntityCheckPresenter.new(entity_check)
      else
        Flapjack::API::EntityPresenter.new(entity, :redis => @@redis)
      end

      presenter.outages(start_time, end_time).to_json
    end

    get %r{/unscheduled_maintenances/([a-zA-Z0-9][a-zA-Z0-9\.\-]*[a-zA-Z0-9])(?:/(\w+))?} do
      content_type :json

      entity_name = params[:captures][0]
      check = params[:captures][1]

      entity = Flapjack::Data::Entity.find_by_name(entity_name, :redis => @@redis)
      if entity.nil?
        status 404
        return
      end

      start_time = validate_and_parsetime(params[:start_time])
      end_time   = validate_and_parsetime(params[:end_time])

      presenter = if check
        entity_check = Flapjack::Data::EntityCheck.for_entity(entity,
          check, :redis => @@redis)
        Flapjack::API::EntityCheckPresenter.new(entity_check)
      else
        Flapjack::API::EntityPresenter.new(entity, :redis => @@redis)
      end

      presenter.unscheduled_maintenance(start_time, end_time).to_json
    end

    get %r{/scheduled_maintenances/([a-zA-Z0-9][a-zA-Z0-9\.\-]*[a-zA-Z0-9])(?:/(\w+))?} do
      content_type :json

      entity_name = params[:captures][0]
      check = params[:captures][1]

      entity = Flapjack::Data::Entity.find_by_name(entity_name, :redis => @@redis)
      if entity.nil?
        status 404
        return
      end

      start_time = validate_and_parsetime(params[:start_time])
      end_time   = validate_and_parsetime(params[:end_time])

      presenter = if check
        entity_check = Flapjack::Data::EntityCheck.for_entity(entity,
          check, :redis => @@redis)
        Flapjack::API::EntityCheckPresenter.new(entity_check)
      else
        Flapjack::API::EntityPresenter.new(entity, :redis => @@redis)
      end
      presenter.scheduled_maintenance(start_time, end_time).to_json
    end

    get %r{/downtime/([a-zA-Z0-9][a-zA-Z0-9\.\-]*[a-zA-Z0-9])(?:/(\w+))?} do
      content_type :json

      entity_name = params[:captures][0]
      check = params[:captures][1]

      entity = Flapjack::Data::Entity.find_by_name(entity_name, :redis => @@redis)
      if entity.nil?
        status 404
        return
      end

      start_time = validate_and_parsetime(params[:start_time])
      end_time   = validate_and_parsetime(params[:end_time])

      presenter = if check
        entity_check = Flapjack::Data::EntityCheck.for_entity(entity,
          check, :redis => @@redis)
        Flapjack::API::EntityCheckPresenter.new(entity_check)
      else
        Flapjack::API::EntityPresenter.new(entity, :redis => @@redis)
      end

      presenter.downtime(start_time, end_time).to_json
    end

    # create a scheduled maintenance period for a service on an entity
    post '/scheduled_maintenances/:entity/:check' do
      content_type :json
      entity = Flapjack::Data::Entity.find_by_name(params[:entity], :redis => @@redis)
      if entity.nil?
        status 404
        return
      end
      entity_check = Flapjack::Data::EntityCheck.for_entity(entity,
        params[:check], :redis => @@redis)
      entity_check.create_scheduled_maintenance(:start_time => params[:start_time],
        :duration => params[:duration], :summary => params[:summary])
      status 204
    end

    # create an acknowledgement for a service on an entity
    # NB currently, this does not acknowledge a specific failure event, just
    # the entity-check as a whole
    post '/acknowledgements/:entity/:check' do
      content_type :json
      entity = Flapjack::Data::Entity.find_by_name(params[:entity], :redis => @@redis)
      if entity.nil?
        status 404
        return
      end

      dur = params[:duration] ? params[:duration].to_i : nil
      duration = (dur.nil? || (dur <= 0)) ? (4 * 60 * 60) : dur

      entity_check = Flapjack::Data::EntityCheck.for_entity(entity,
        params[:check], :redis => @@redis)
      entity_check.create_acknowledgement('summary' => params[:summary],
        'duration' => duration)
      status 204
    end

    not_found do
      [404, {}, {:status => 404, :reason => "Not found"}.to_json]
    end

    private

      def entity_check_status(entity, check)
        entity_check = Flapjack::Data::EntityCheck.for_entity(entity,
          check, :redis => @@redis)
        return if entity_check.nil?
        { 'name'                                => check,
          'state'                               => entity_check.state,
          'in_unscheduled_maintenance'          => entity_check.in_unscheduled_maintenance?,
          'in_scheduled_maintenance'            => entity_check.in_scheduled_maintenance?,
          'last_update'                         => entity_check.last_update,
          'last_problem_notification'           => entity_check.last_problem_notification,
          'last_recovery_notification'          => entity_check.last_recovery_notification,
          'last_acknowledgement_notification'   => entity_check.last_acknowledgement_notification
        }
      end

      # NB: casts to UTC before converting to a timestamp
      def validate_and_parsetime(value)
        return unless value
        Time.iso8601(value).getutc.to_i
      rescue ArgumentError => e
        logger.error "Couldn't parse time from '#{value}'"
        nil
      end

  end

end
