#!/usr/bin/env ruby

require 'rubygems'
require 'bundler/setup'
require 'sinatra/base'
require 'sinatra_more/markup_plugin'
require 'redis'

module Flapjack
  class Web < Sinatra::Base
    register SinatraMore::MarkupPlugin

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

    before do
      @persistence = ::Redis.new
    end

    get '/' do
      @keys = @persistence.keys '*'
      @count = @persistence.zcard 'failed_services'
      @events_queued = @persistence.llen('events')
      @states = @persistence.keys('*:*:states').map { |r|
        parts   = r.split(':')[0..1]
        key     = parts.join(':')
        data    = @persistence.hmget(key, 'state', 'last_change', 'last_update')
        parts  += data
      }.sort_by {|parts| parts }
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
      haml :index
    end
  end
end
