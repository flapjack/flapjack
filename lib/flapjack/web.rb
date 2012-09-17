#!/usr/bin/env ruby

require 'chronic'
require 'chronic_duration'
require 'sinatra/base'
require 'haml'

require 'flapjack/pikelet'
require 'flapjack/data/entity_check'

module Flapjack
  class Web < Sinatra::Base

    use Rack::MethodOverride

    extend Flapjack::Pikelet

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
      @entity = params[:entity]
      @check = params[:check]

      entity_check = get_entity_check(@entity, @check)
      return 404 if entity_check.nil?

      @check_state                = entity_check.state
      @check_last_update          = entity_check.last_update
      @check_last_change          = entity_check.last_change
      @check_summary              = entity_check.summary
      @last_notifications         =
        {:problem         => entity_check.last_problem_notification,
         :recovery        => entity_check.last_recovery_notification,
         :acknowledgement => entity_check.last_acknowledgement_notification
        }
      @in_scheduled_maintenance   = entity_check.in_scheduled_maintenance?
      @in_unscheduled_maintenance = entity_check.in_unscheduled_maintenance?
      @scheduled_maintenances     = entity_check.maintenances(nil, nil, :scheduled => true)

      haml :check
    end

    post '/acknowledgements/:entity/:check' do
      @entity = params[:entity]
      @check = params[:check]

      entity_check = get_entity_check(@entity, @check)
      return 404 if entity_check.nil?

      ack = entity_check.create_acknowledgement('summary' => "Ack from web at #{Time.now.to_s}")
      @acknowledge_success = !!ack
      [201, haml(:acknowledge)]
    end

    # FIXME: there is bound to be a more idiomatic / restful way of doing this
    post '/end_unscheduled_maintenance/:entity/:check' do
      @entity = params[:entity]
      @check = params[:check]

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

      entity_check = get_entity_check(params[:entity],  params[:check])
      return 404 if entity_check.nil?

      entity_check.create_scheduled_maintenance(:start_time => start_time,
                                                :duration   => duration,
                                                :summary    => summary)
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

    # Returns relative time in words referencing the given date
    # relative_time_ago(Time.now) => 'about a minute ago'
    def relative_time_ago(from_time)
      distance_in_minutes = (((Time.now - from_time.to_time).abs)/60).round
      case distance_in_minutes
        when 0..1 then 'about a minute'
        when 2..44 then "#{distance_in_minutes} minutes"
        when 45..89 then 'about 1 hour'
        when 90..1439 then "about #{(distance_in_minutes.to_f / 60.0).round} hours"
        when 1440..2439 then '1 day'
        when 2440..2879 then 'about 2 days'
        when 2880..43199 then "#{(distance_in_minutes / 1440).round} days"
        when 43200..86399 then 'about 1 month'
        when 86400..525599 then "#{(distance_in_minutes / 43200).round} months"
        when 525600..1051199 then 'about 1 year'
        else "over #{(distance_in_minutes / 525600).round} years"
      end
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
