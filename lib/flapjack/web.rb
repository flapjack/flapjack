#!/usr/bin/env ruby

require 'bundler/setup'
require 'sinatra/base'
require 'sinatra_more/markup_plugin'
require 'redis'
require 'resque'
require 'flapjack/redis'

module Flapjack
  class Web < Sinatra::Base
    register SinatraMore::MarkupPlugin

    include Flapjack::Redis

    set :views, settings.root + '/web/views'

    def time_period_in_words(period)
      period_mm, period_ss = @uptime.divmod(60)
      period_hh, period_mm = period_mm.divmod(60)
      period_dd, period_hh = period_hh.divmod(24)
      period_string         = ""
      period_string        += period_dd.to_s + " days, " if period_dd > 0
      period_string        += period_hh.to_s + " hours, " if period_hh > 0
      period_string        += period_mm.to_s + " minutes, " if period_mm > 0
      period_string        += period_ss.to_s + " seconds" if period_ss > 0
      period_string
    end

    def self_stats
      @keys  = @persistence.keys '*'
      @count_failing_checks  = @persistence.zcard 'failed_checks'
      @count_all_checks      = 'heaps' # FIXME: rename ENTITY:CHECK to check:ENTITY:CHECK so we can glob them here,
                                       # or create a set to index all checks
      @event_counter_all     = @persistence.hget('event_counters', 'all')
      @event_counter_ok      = @persistence.hget('event_counters', 'ok')
      @event_counter_failure = @persistence.hget('event_counters', 'failure')
      @event_counter_action  = @persistence.hget('event_counters', 'action')
      @boot_time             = Time.at(@persistence.get('boot_time').to_i)
      @uptime                = Time.now.to_i - @boot_time.to_i
      @uptime_string         = time_period_in_words(@uptime)
      if @uptime > 0
        @event_rate_all      = @event_counter_all.to_f / @uptime
      else
        @event_rate_all      = 0
      end
      @events_queued = @persistence.llen('events')
    end

    def last_notifications(event_id)
      notifications = {}
      notifications[:problem]         = @persistence.get("#{event_id}:last_problem_notification").to_i
      notifications[:recovery]        = @persistence.get("#{event_id}:last_recovery_notification").to_i
      notifications[:acknowledgement] = @persistence.get("#{event_id}:last_acknowledgement_notification").to_i
      return notifications
    end

    def last_notification(event_id)
      notifications = last_notifications(event_id)
      return notifications.sort_by {|kind, timestamp| timestamp}.last
    end

    def check_summary(event_id)
      timestamp = @persistence.lindex("#{event_id}:states", -1)
      @persistence.get("#{event_id}:#{timestamp}:summary")
    end

    before do
      @persistence = ::Redis.new
    end

    get '/' do
      self_stats
      @states = @persistence.keys('*:*:states').map { |r|
        parts   = r.split(':')[0..1]
        key     = parts.join(':')
        parts  += @persistence.hmget(key, 'state', 'last_change', 'last_update')
        parts  << in_unscheduled_maintenance?(key)
        parts  << in_scheduled_maintenance?(key)
        parts  += last_notification(key)
      }.sort_by {|parts| parts }
      haml :index
    end

    get '/failing' do
      self_stats
      @states = @persistence.zrange('failed_checks', 0, -1).map {|key|
        parts   = key.split(':')
        parts  += @persistence.hmget(key, 'state', 'last_change', 'last_update')
        parts  << in_unscheduled_maintenance?(key)
        parts  << in_scheduled_maintenance?(key)
        parts  += last_notification(key)
      }.sort_by {|parts| parts}
      haml :index
    end

    get '/check' do
      @entity = params[:entity]
      @check  = params[:check]
      key = @entity + ":" + @check
      @check_state        = @persistence.hget(key, 'state')
      @check_last_update  = @persistence.hget(key, 'last_update')
      @check_last_change  = @persistence.hget(key, 'last_change')
      @check_summary      = check_summary(key)
      @last_notifications = last_notifications(key)
      @in_unscheduled_maintenance = in_unscheduled_maintenance?(key)
      @in_scheduled_maintenance   = in_scheduled_maintenance?(key)
      haml :check
    end

    get '/self_stats' do
      self_stats
      haml :self_stats
    end

    get '/acknowledge' do
      @entity = params[:entity]
      @check  = params[:check]
      key = @entity + ":" + @check
      ack_opts = { 'summary' => "Ack from web at #{Time.now.to_s}" }
      if create_acknowledgement(key, ack_opts)
        @acknowledge_success = true
      else
        @acknowledge_success = false
      end
      haml :acknowledge
    end

  end
end
