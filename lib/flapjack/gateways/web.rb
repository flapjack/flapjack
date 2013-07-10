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
      set :public_folder, settings.root + '/web/public'

      def redis
        self.class.instance_variable_get('@redis')
      end

      def logger
        self.class.instance_variable_get('@logger')
      end

      get '/' do
        check_stats
        entity_stats
        haml :index
      end

      get '/checks_all' do
        check_stats
        @adjective = 'all'

        # TODO (?) recast as Entity.all do |e|; e.checks.do |ec|; ...
        @states = redis.keys('*:*:states').map { |r|
          entity, check = r.sub(/:states$/, '').split(':', 2)
          [entity, check] + entity_check_state(entity, check)
        }.compact.sort_by {|parts| parts }

        haml :checks
      end

      get '/checks_failing' do
        check_stats
        @adjective = 'failing'

        @states = redis.zrange('failed_checks', 0, -1).map {|key|
          parts  = key.split(':', 2)
          [parts[0], parts[1]] + entity_check_state(parts[0], parts[1])
        }.compact.sort_by {|parts| parts}

        haml :checks
      end

      get '/self_stats' do
        self_stats
        entity_stats
        check_stats
        haml :self_stats
      end

      get '/self_stats.json' do
        self_stats
        entity_stats
        check_stats
        {
          'events_queued'    => @events_queued,
          'all_entities'     => @count_all_entities,
          'failing_entities' => @count_failing_entities,
          'all_checks'       => @count_all_checks,
          'failing_checks'   => @count_failing_checks,
          'processed_events' => {
            'all_time' => {
              'total'   => @event_counters['all'].to_i,
              'ok'      => @event_counters['ok'].to_i,
              'failure' => @event_counters['failure'].to_i,
              'action'  => @event_counters['action'].to_i,
            }
          },
          'total_keys' => @dbsize,
          'uptime'     => @uptime_string,
          'boottime'   => @boot_time,
          'current_time' => Time.now,
          'executive_instances' => @executive_instances,
        }.to_json
      end

      get '/entities_all' do
        entity_stats
        @adjective = 'all'
        @entities = Flapjack::Data::Entity.find_all_with_checks(:redis => redis)
        haml :entities
      end

      get '/entities_failing' do
        entity_stats
        @adjective = 'failing'
        @entities = Flapjack::Data::Entity.find_all_with_failing_checks(:redis => redis)
        haml :entities
      end

      get '/entity/:entity' do
        @entity = params[:entity]
        entity_stats
        @states = redis.keys("#{@entity}:*:states").map { |r|
          check = r.sub(/^#{@entity}:/, '').sub(/:states$/, '')
          [@entity, check] + entity_check_state(@entity, check)
        }.compact.sort_by {|parts| parts }
        haml :entity
      end

      get '/check' do
        @entity = params[:entity]
        @check  = params[:check]

        entity_check = get_entity_check(@entity, @check)
        return 404 if entity_check.nil?

        check_stats

        last_change = entity_check.last_change

        @check_state                = entity_check.state
        @check_enabled              = entity_check.enabled?
        @check_last_update          = entity_check.last_update
        @check_last_change          = last_change
        @check_summary              = entity_check.summary
        @check_details              = entity_check.details
        @last_notifications         = entity_check.last_notifications_of_each_type
        @scheduled_maintenances     = entity_check.maintenances(nil, nil, :scheduled => true)
        @acknowledgement_id         = entity_check.failed? ?
          entity_check.event_count_at(entity_check.last_change) : nil

        @current_scheduled_maintenance   = entity_check.current_maintenance(:scheduled => true)
        @current_unscheduled_maintenance = entity_check.current_maintenance(:scheduled => false)

        @contacts                   = entity_check.contacts

        @state_changes = entity_check.historical_states(nil, Time.now.to_i,
                           :order => 'desc', :limit => 20)

        haml :check
      end

      post '/acknowledgements/:entity/:check' do
        @entity             = params[:entity]
        @check              = params[:check]
        @summary            = params[:summary]
        @acknowledgement_id = params[:acknowledgement_id]

        dur = ChronicDuration.parse(params[:duration] || '')
        @duration = (dur.nil? || (dur <= 0)) ? (4 * 60 * 60) : dur

        return 404 if get_entity_check(@entity, @check).nil?

        ack = Flapjack::Data::Event.create_acknowledgement(
          @entity, @check,
          :summary => (@summary || ''),
          :acknowledgement_id => @acknowledgement_id,
          :duration => @duration,
          :redis => redis)

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

      # delete a scheduled maintenance
      delete '/scheduled_maintenances/:entity/:check' do
        entity_check = get_entity_check(params[:entity], params[:check])
        return 404 if entity_check.nil?

        entity_check.end_scheduled_maintenance(params[:start_time].to_i)
        redirect back
      end

      # delete a check (actually just disables it)
      delete '/checks/:entity/:check' do
        entity_check = get_entity_check(params[:entity], params[:check])
        return 404 if entity_check.nil?

        entity_check.disable!
        redirect back
      end

      get '/contacts' do
        #self_stats
        @contacts = Flapjack::Data::Contact.all(:redis => redis)
        haml :contacts
      end

      get "/contacts/:contact" do
        #self_stats
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
          {:problem         => entity_check.last_notification_for_state(:problem)[:timestamp],
           :recovery        => entity_check.last_notification_for_state(:recovery)[:timestamp],
           :acknowledgement => entity_check.last_notification_for_state(:acknowledgement)[:timestamp]
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

        @dbsize                  = redis.dbsize
        @executive_instances     = redis.keys("executive_instance:*").map {|i|
          [ i.match(/executive_instance:(.*)/)[1], redis.hget(i, 'boot_time').to_i ]
        }.sort {|a, b| b[1] <=> a[1]}
        @event_counters          = redis.hgetall('event_counters')
        @event_counters_instance = redis.hgetall("event_counters:#{@instance_id}")
        @boot_time               = Time.at(redis.hget("executive_instance:#{@instance_id}", 'boot_time').to_i)
        @uptime                  = Time.now.to_i - @boot_time.to_i
        @uptime_string           = time_period_in_words(@uptime)
        @event_rate_all          = (@uptime > 0) ?
                                   (@event_counters_instance['all'].to_f / @uptime) : 0
        @events_queued           = redis.llen('events')
      end

      def entity_stats
        @count_all_entities      = Flapjack::Data::Entity.find_all_with_checks(:redis => redis).length
        @count_failing_entities  = Flapjack::Data::Entity.find_all_with_failing_checks(:redis => redis).length
      end

      def check_stats
        @count_all_checks        = redis.keys('check:*:*').length
        @count_failing_checks    = redis.zcard 'failed_checks'
      end


    end

  end

end
