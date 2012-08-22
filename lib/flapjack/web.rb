#!/usr/bin/env ruby

require 'chronic'
require 'chronic_duration'

require 'flapjack/pikelet'
require 'flapjack/models/entity_check'

module Flapjack
  class Web < Sinatra::Base
    register SinatraMore::MarkupPlugin

    extend Flapjack::Pikelet

    set :views, settings.root + '/web/views'

    # TODO move these to a time handling section of a utils lib
    def time_period_in_words(period)
      period_mm, period_ss  = period.divmod(60)
      period_hh, period_mm  = period_mm.divmod(60)
      period_dd, period_hh  = period_hh.divmod(24)
      period_string         = ""
      period_string        += period_dd.to_s + " days, " if period_dd > 0
      period_string        += period_hh.to_s + " hours, " if period_hh > 0
      period_string        += period_mm.to_s + " minutes, " if period_mm > 0
      period_string        += period_ss.to_s + " seconds" if period_ss > 0
      period_string
    end

    # returns a string showing the local timezone we're running in
    # eg "CST (UTC+09:30)"
    def local_timezone
      tzname = Time.new.zone
      q, r = Time.new.utc_offset.divmod(3600)
      q < 0 ? sign = '-' : sign = '+'
      tzoffset = sign + "%02d" % q.abs.to_s + ':' + r.to_f.div(60).to_s
      "#{tzname} (UTC#{tzoffset})"
    end

    def self_stats
      @keys = redis.keys '*'
      @count_failing_checks  = redis.zcard 'failed_checks'
      @count_all_checks      = 'heaps' # FIXME: rename ENTITY:CHECK to check:ENTITY:CHECK so we can glob them here,
                                       # or create a set to index all checks
      @event_counter_all     = redis.hget('event_counters', 'all')
      @event_counter_ok      = redis.hget('event_counters', 'ok')
      @event_counter_failure = redis.hget('event_counters', 'failure')
      @event_counter_action  = redis.hget('event_counters', 'action')
      @boot_time             = Time.at(redis.get('boot_time').to_i)
      @uptime                = Time.now.to_i - @boot_time.to_i
      @uptime_string         = time_period_in_words(@uptime)
      @event_rate_all        = (@uptime > 0) ?
                                 (@event_counter_all.to_f / @uptime) : 0
      @events_queued = redis.llen('events')
    end

    def redis
      Flapjack::Web.persistence
    end

     def logger
      Flapjack::Web.logger
    end

    before do
      # will only initialise the first time it's run
      Flapjack::Web.bootstrap(:redis => {:driver => :ruby})
    end

    after do
    end

    get '/' do
      self_stats
      @states = redis.keys('*:*:states').map { |r|
        parts   = r.split(':')[0..1]
        entity_check = EntityCheck.new(:entity => parts[0], :check => parts[1], :redis => redis)
        key     = parts.join(':')
        parts  += redis.hmget(key, 'state', 'last_change', 'last_update')
        parts  << entity_check.in_unscheduled_maintenance?
        parts  << entity_check.in_scheduled_maintenance?
        parts  += entity_check.last_notification
      }.sort_by {|parts| parts }
      haml :index
    end

    get '/failing' do
      self_stats
      @states = redis.zrange('failed_checks', 0, -1).map {|key|
        parts   = key.split(':')
        entity_check = EntityCheck.new(:entity => parts[0], :check => parts[1], :redis => redis)
        parts  += redis.hmget(key, 'state', 'last_change', 'last_update')
        parts  << entity_check.in_unscheduled_maintenance?
        parts  << entity_check.in_scheduled_maintenance?
        parts  += entity_check.last_notification
      }.sort_by {|parts| parts}
      haml :index
    end

    get '/self_stats' do
      self_stats
      haml :self_stats
    end

    get '/check' do
      @entity = params[:entity]
      @check  = params[:check]

      entity_check = EntityCheck.new(:entity => @entity, :check => @check, :redis => redis)
      @status = entity_check.status

      @check_state                = @status[:state]
      @check_last_update          = @status[:last_update]
      @check_last_change          = @status[:last_change]
      @check_summary              = @status[:summary]
      @last_notifications         = @status[:last_notifications]
      @in_unscheduled_maintenance = @status[:in_scheduled_maintenance]
      @in_scheduled_maintenance   = @status[:in_unscheduled_maintenance]
      @scheduled_maintenances     = @status[:scheduled_maintenances]

      haml :check
    end

    get '/acknowledge' do
      @entity = params[:entity]
      @check  = params[:check]
      entity_check = EntityCheck.new(:entity => @entity, :check => @check, :redis => redis)
      ack = entity_check.create_acknowledgement(:summary => "Ack from web at #{Time.now.to_s}")
      @acknowledge_success = !!ack
      haml :acknowledge
    end

    # create scheduled maintenance
    post '/scheduled_maintenance/:entity/:check' do
      start_time = Chronic.parse(params[:start_time]).to_i
      raise ArgumentError, "start time parsed to zero" unless start_time > 0
      duration   = ChronicDuration.parse(params[:duration])
      summary    = params[:summary]
      entity = params[:entity]
      check  = params[:check]
      entity_check = EntityCheck.new(:entity => entity, :check => check, :redis => redis)
      entity_check.create_scheduled_maintenance(:start_time => start_time,
                                                :duration   => duration,
                                                :summary    => summary)
      redirect back
    end

    # delete a scheduled maintenance
    post '/delete_scheduled_maintenance/:entity/:check' do
      entity = params[:entity]
      check  = params[:check]
      entity_check = EntityCheck.new(:entity => entity, :check => check, :redis => redis)
      start_time = params[:start_time]
      entity_check.delete_scheduled_maintenance(:start_time => start_time)
      redirect back
    end
  end
end
