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

    before do
      @persistence = ::Redis.new
    end

    get '/' do
      @keys = @persistence.keys '*'
      @count = @persistence.zcard 'failed_services'
      @events_queued = @persistence.llen('events')
      @states = @persistence.keys('*:*:states').map { |r|
        parts  = r.split(':')[0..1]
        key    = parts.join(':')
        data   = @persistence.hmget(key, 'state', 'last_change')
        parts += data
      }.sort_by {|parts| parts.first }

      haml :index
    end
  end
end
