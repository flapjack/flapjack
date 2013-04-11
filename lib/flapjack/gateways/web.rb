#!/usr/bin/env ruby

require 'chronic'
require 'chronic_duration'
require 'sinatra/base'
require 'haml'
require 'rack/fiber_pool'

require 'flapjack/rack_logger'

require 'flapjack/data/contact'
require 'flapjack/data/entity_check'
require 'flapjack/redis_pool'
require 'flapjack/utility'

module Flapjack

  module Gateways

    class Web < Sinatra::Base

      rescue_exception = Proc.new do |env, e|
        if settings.show_exceptions?
          # ensure the sinatra error page shows properly
          request = Sinatra::Request.new(env)
          printer = Sinatra::ShowExceptions.new(proc{ raise e })
          s, h, b = printer.call(env)
          [s, h, b]
        else
          @logger.error e.message
          @logger.error e.backtrace.join("\n")
          [503, {}, ""]
        end
      end
      use Rack::FiberPool, :size => 25, :rescue_exception => rescue_exception

      use Rack::MethodOverride

      class << self
        def start
          @redis = Flapjack::RedisPool.new(:config => @redis_config, :size => 1)

          @logger.info "starting web - class"

          if accesslog = (@config && @config['access_log'])
            if not File.directory?(File.dirname(accesslog))
              puts "Parent directory for log file #{accesslog} doesn't exist"
              puts "Exiting!"
              exit
            end

            access_logger = Flapjack::AsyncLogger.new(@config['access_log'])
            use Flapjack::CommonLogger, access_logger
          end

        end
      end

      include Flapjack::Utility

      set :views, settings.root + '/web/views'

      def redis
        self.class.instance_variable_get('@redis')
      end

      def logger
        self.class.instance_variable_get('@logger')
      end

      get '/' do
        self_stats

        # TODO (?) recast as Entity.all do |e|; e.checks.do |ec|; ...
        @states = redis.keys('*:*:states').map { |r|
          parts  = r.split(':')[0..1]
          [parts[0], parts[1]] + entity_check_state(parts[0], parts[1])
        }.compact.sort_by {|parts| parts }

        haml :index
      end

      get '/failing' do
        self_stats
        @states = redis.zrange('failed_checks', 0, -1).map {|key|
          parts  = key.split(':')
          [parts[0], parts[1]] + entity_check_state(parts[0], parts[1])
        }.compact.sort_by {|parts| parts}
        haml :index
      end

      get '/self_stats' do
        self_stats
        haml :self_stats
      end

      get '/self_stats.json' do
        self_stats

        {
          'events_queued'    => @events_queued,
          'failing_services' => @count,
          'processed_events' => {
            'all_time' => {
              'total'   => @event_counters['all'],
              'ok'      => @event_counters['ok'],
              'failure' => @event_counters['failure'],
              'action'  => @event_counters['action'],
            },
            'instance' => {
              'total'   => @event_counters_instance['all'],
              'ok'      => @event_counters_instance['ok'],
              'failure' => @event_counters_instance['failure'],
              'action'  => @event_counters_instance['action'],
              'average' => @event_rate_all,
            }
          },
          'total_keys' => @keys.length,
          'uptime'     => @uptime_string,
          'boottime'   => @boot_time,
          'current_time' => Time.now,
          'executive_instances' => @executive_instances,
        }.to_json
      end

      get '/check' do
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

        @contacts                   = entity_check.contacts

        haml :check
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
      # (probably using 'delete' or 'patch')
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

      get '/contacts' do
        @contacts = Flapjack::Data::Contact.all(:redis => redis)
        haml :contacts
      end

      get "/contacts/:contact" do
        contact_id = params[:contact]

        if contact_id
          @contact = Flapjack::Data::Contact.find_by_id(contact_id, :redis => redis)
        end

        unless @contact
          status 404
          return
        end

        if @contact.media.has_key?('pagerduty')
          @pagerduty_credentials = @contact.pagerduty_credentials
        end

        @entities_and_checks = @contact.entities(:checks => true).sort_by {|ec|
          ec[:entity].name
        }

        haml :contact
      end

    protected

      def render_haml(file, scope)
        Haml::Engine.new(File.read(File.dirname(__FILE__) + '/web/views/' + file)).render(scope)
      end

    private

      def get_entity_check(entity, check)
        entity_obj = (entity && entity.length > 0) ?
          Flapjack::Data::Entity.find_by_name(entity, :redis => redis) : nil
        return if entity_obj.nil? || (check.nil? || check.length == 0)
        Flapjack::Data::EntityCheck.for_entity(entity_obj, check, :redis => redis)
      end

      def entity_check_state(entity_name, check)
        entity = Flapjack::Data::Entity.find_by_name(entity_name,
          :redis => redis)
        return if entity.nil?
        entity_check = Flapjack::Data::EntityCheck.for_entity(entity,
          check, :redis => redis)
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
        @fqdn         = `/bin/hostname -f`.chomp
        @pid          = Process.pid
        @instance_id  = "#{@fqdn}:#{@pid}"

        @keys = redis.keys '*'
        @count_failing_checks    = redis.zcard 'failed_checks'
        @count_all_checks        = redis.keys('check:*:*').length
        @executive_instances     = redis.zrange('executive_instances', '0', '-1', :withscores => true)
        @event_counters          = redis.hgetall('event_counters')
        @event_counters_instance = redis.hgetall("event_counters:#{@instance_id}")
        @boot_time               = Time.at(redis.zscore('executive_instances', @instance_id).to_i)
        @uptime                  = Time.now.to_i - @boot_time.to_i
        @uptime_string           = time_period_in_words(@uptime)
        @event_rate_all          = (@uptime > 0) ?
                                   (@event_counters_instance['all'].to_f / @uptime) : 0
        @events_queued = redis.llen('events')
      end

    end

  end

end
