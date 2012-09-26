#!/usr/bin/env ruby

require 'fiber'

require 'chronic'
require 'chronic_duration'
require 'sinatra/base'
require 'haml'
require 'rack/fiber_pool'

require 'flapjack/pikelet'
require 'flapjack/data/entity_check'
require 'flapjack/utility'

module Flapjack
  class Web < Sinatra::Base

    # doesn't work with Rack::Test for some reason
    unless 'test'.eql?(FLAPJACK_ENV)
      rescue_exception = Proc.new { |env, exception|
        logger.error exception.message
        logger.error exception.backtrace.join("\n")
        [503, {}, exception.message]
      }

      use Rack::FiberPool, :size => 25, :rescue_exception => rescue_exception
    end
    use Rack::MethodOverride
    extend Flapjack::Pikelet
    include Flapjack::Utility

    set :views, settings.root + '/web/views'

    before do
      # will only initialise the first time it's run
      Flapjack::Web.bootstrap
    end

    get '/' do
      self_stats

      # TODO (?) recast as Entity.all do |e|; e.checks.do |ec|; ...
      @states = @@redis.keys('*:*:states').map { |r|
        parts  = r.split(':')[0..1]
        [parts[0], parts[1]] + entity_check_state(parts[0], parts[1])
      }.compact.sort_by {|parts| parts }
      haml :index
    end

    get '/failing' do
      self_stats
      @states = @@redis.zrange('failed_checks', 0, -1).map {|key|
        parts  = key.split(':')
        [parts[0], parts[1]] + entity_check_state(parts[0], parts[1])
      }.compact.sort_by {|parts| parts}
      haml :index
    end

    get '/self_stats' do
      self_stats
      haml :self_stats
    end

    get '/check' do
      #begin
      @entity = params[:entity]
      @check  = params[:check]

      entity_check = get_entity_check(@entity, @check)
      return 404 if entity_check.nil?

      last_change = entity_check.last_change

      @check_state                = entity_check.state
      @check_last_update          = entity_check.last_update
      @check_last_change          = last_change
      @check_summary              = entity_check.summary
      @last_notifications         = entity_check.last_notifications_of_each_type
      @scheduled_maintenances     = entity_check.maintenances(nil, nil, :scheduled => true)
      @acknowledgement_id         = entity_check.failed? ?
        entity_check.event_count_at(entity_check.last_change) : nil

      @current_scheduled_maintenance   = entity_check.current_maintenance(:scheduled => true)
      @current_unscheduled_maintenance = entity_check.current_maintenance(:scheduled => false)

      haml :check
      #rescue Exception => e
      #  puts e.message
      #  puts e.backtrace.join("\n")
      #end

    end

    post '/acknowledgements/:entity/:check' do
      @entity             = params[:entity]
      @check              = params[:check]
      @summary            = params[:summary]
      @acknowledgement_id = params[:acknowledgement_id]

      dur = ChronicDuration.parse(params[:duration] || '')
      @duration = (dur.nil? || (dur <= 0)) ? (4 * 60 * 60) : dur

      entity_check = get_entity_check(@entity, @check)
      return 404 if entity_check.nil?

      ack = entity_check.create_acknowledgement('summary' => (@summary || ''),
        'acknowledgement_id' => @acknowledgement_id, 'duration' => @duration)

      redirect back
    end

    # FIXME: there is bound to be a more idiomatic / restful way of doing this
    post '/end_unscheduled_maintenance/:entity/:check' do
      @entity = params[:entity]
      @check  = params[:check]

      entity_check = get_entity_check(@entity, @check)
      return 404 if entity_check.nil?

      entity_check.end_unscheduled_maintenance

      redirect back
    end

    # create scheduled maintenance
    post '/scheduled_maintenances/:entity/:check' do
      start_time = Chronic.parse(params[:start_time]).to_i
      raise ArgumentError, "start time parsed to zero" unless start_time > 0
      duration   = ChronicDuration.parse(params[:duration])
      summary    = params[:summary]

      entity_check = get_entity_check(params[:entity], params[:check])
      return 404 if entity_check.nil?

      entity_check.create_scheduled_maintenance(:start_time => start_time,
                                                :duration   => duration,
                                                :summary    => summary)
      redirect back
    end

    # modify scheduled maintenance
    patch '/scheduled_maintenances/:entity/:check' do
      entity_check = get_entity_check(params[:entity], params[:check])
      return 404 if entity_check.nil?

      end_time   = Chronic.parse(params[:end_time]).to_i
      start_time = params[:start_time].to_i
      raise ArgumentError, "start time parsed to zero" unless start_time > 0

      patches = {}
      patches[:end_time] = end_time if end_time && (end_time > start_time)

      raise ArgumentError.new("no valid data received to patch with") if patches.empty?

      entity_check.update_scheduled_maintenance(start_time, patches)
      redirect back
    end

    # delete a scheduled maintenance
    delete '/scheduled_maintenances/:entity/:check' do
      entity_check = get_entity_check(params[:entity], params[:check])
      return 404 if entity_check.nil?

      entity_check.delete_scheduled_maintenance(:start_time => params[:start_time].to_i)
      redirect back
    end

  private

    def get_entity_check(entity, check)
      entity_obj = (entity && entity.length > 0) ?
        Flapjack::Data::Entity.find_by_name(entity, :redis => @@redis) : nil
      return if entity_obj.nil? || (check.nil? || check.length == 0)
      Flapjack::Data::EntityCheck.for_entity(entity_obj, check, :redis => @@redis)
    end

    def entity_check_state(entity_name, check)
      entity = Flapjack::Data::Entity.find_by_name(entity_name,
        :redis => @@redis)
      return if entity.nil?
      entity_check = Flapjack::Data::EntityCheck.for_entity(entity,
        check, :redis => @@redis)
      latest_notif =
        {:problem         => entity_check.last_problem_notification,
         :recovery        => entity_check.last_recovery_notification,
         :acknowledgement => entity_check.last_acknowledgement_notification
        }.max_by {|n| n[1] || 0}
      [(entity_check.state       || '-'),
       (entity_check.last_change || '-'),
       (entity_check.last_update || '-'),
       entity_check.in_unscheduled_maintenance?,
       entity_check.in_scheduled_maintenance?,
       latest_notif[0],
       latest_notif[1]
      ]
    end

    def self_stats
      @keys = @@redis.keys '*'
      @count_failing_checks  = @@redis.zcard 'failed_checks'
      @count_all_checks      = @@redis.keys('check:*:*').length
      @event_counter_all     = @@redis.hget('event_counters', 'all')
      @event_counter_ok      = @@redis.hget('event_counters', 'ok')
      @event_counter_failure = @@redis.hget('event_counters', 'failure')
      @event_counter_action  = @@redis.hget('event_counters', 'action')
      @boot_time             = Time.at(@@redis.get('boot_time').to_i)
      @uptime                = Time.now.to_i - @boot_time.to_i
      @uptime_string         = time_period_in_words(@uptime)
      @event_rate_all        = (@uptime > 0) ?
                                 (@event_counter_all.to_f / @uptime) : 0
      @events_queued = @@redis.llen('events')
    end

    def logger
      Flapjack::Web.logger
    end

  end
end
