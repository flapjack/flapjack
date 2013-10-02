#!/usr/bin/env ruby

require 'chronic'
require 'chronic_duration'
require 'sinatra/base'
require 'erb'

require 'flapjack'

require 'flapjack/data/contact_r'
require 'flapjack/data/entity_check_r'
require 'flapjack/utility'

module Flapjack

  module Gateways

    class Web < Sinatra::Base
      set :raise_errors, true

      use Rack::MethodOverride

      class << self
        def start
          @logger.info "starting web - class"

          if accesslog = (@config && @config['access_log'])
            if not File.directory?(File.dirname(accesslog))
              puts "Parent directory for log file #{accesslog} doesn't exist"
              puts "Exiting!"
              exit
            end

            use Rack::CommonLogger, ::Logger.new(@config['access_log'])
          end
        end
      end

      include Flapjack::Utility

      set :views, settings.root + '/web/views'
      set :public_folder, settings.root + '/web/public'

      helpers do
        def h(text)
          ERB::Util.h(text)
        end

        def u(text)
          ERB::Util.u(text)
        end
      end

      ['logger', 'config'].each do |class_inst_var|
        define_method(class_inst_var.to_sym) do
          self.class.instance_variable_get("@#{class_inst_var}")
        end
      end

      get '/' do
        check_stats
        entity_stats

        erb 'index.html'.to_sym
      end

      get '/checks_all' do
        check_stats
        @adjective = 'all'

        checks_by_entity = Flapjack::Data::EntityCheckR.hash_by_entity_name( Flapjack::Data::EntityCheckR.all )
        @entities_sorted = checks_by_entity.keys.sort
        @states = checks_by_entity.inject({}) {|result, (entity_name, checks)|
          result[entity_name] = checks.sort_by(&:name).map {|check|
            [check.name] + entity_check_state(entity_check)
          }
          result
        }

        erb 'checks.html'.to_sym
      end

      get '/checks_failing' do
        check_stats
        @adjective = 'failing'

        failing_checks = Flapjack::Data::EntityCheckR.
          union(:state => Flapjack::Data::CheckStateR.failing_states.collect).all

        checks_by_entity = Flapjack::Data::EntityCheckR.hash_by_entity_name( failing_checks )
        @entities_sorted = checks_by_entity.keys.sort
        @states = checks_by_entity.inject({}) {|result, (entity_name, checks)|
          result[entity_name] = checks.sort_by(&:name).map {|check|
            [check.name] + entity_check_state(entity_check)
          }
          result
        }

        erb 'checks.html'.to_sym
      end

      get '/self_stats' do
        self_stats
        entity_stats
        check_stats

        erb 'self_stats.html'.to_sym
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
        @entities = Flapjack::Data::EntityR.intersect(:enabled => true).all.
          map(&:name).sort

        erb 'entities.html'.to_sym
      end

      get '/entities_failing' do
        entity_stats
        @adjective = 'failing'
        failing_checks = Flapjack::Data::EntityCheckR.
          union(:state => Flapjack::Data::CheckStateR.failing_states.collect).all

        checks_by_entity = Flapjack::Data::EntityCheckR.hash_by_entity_name( failing_checks )

        @entities = checks_by_entity.keys.sort

        erb 'entities.html'.to_sym
      end

      get '/entity/:entity' do
        @entity = params[:entity]
        entity_stats

        @states = Flapjack::Data::EntityCheckR.
          intersect(:entity_name => @entity).all.sort_by(&:name).map { |entity_check|
          [entity_check.name] + entity_check_state(entity_check)
        }.sort_by {|parts| parts }

        erb 'entity.html'.to_sym
      end

      get '/check' do
        @entity = params[:entity]
        @check  = params[:check]

        entity_check = Flapjack::Data::EntityCheckR.intersect(:entity_name => @entity,
          :name => @check).all.first
        return 404 if entity_check.nil?

        check_stats

        last_change = entity_check.last_change
        last_update = entity_check.states.last

        @check_state                = entity_check.state
        @check_enabled              = !!entity_check.enabled
        @check_last_update          = last_update ? last_update.timestamp : nil
        @check_last_change          = last_change ? last_change.timestamp : nil
        @check_summary              = entity_check.summary
        @check_details              = entity_check.details

        @last_notifications         = last_notification_data(entity_check)

        @scheduled_maintenances     = entity_check.scheduled_maintenances_by_start.all
        @acknowledgement_id         = entity_check.failed? ? last_change.count : nil

        @current_scheduled_maintenance   = entity_check.current_scheduled_maintenance
        @current_unscheduled_maintenance = entity_check.current_unscheduled_maintenance

        @contacts                   = entity_check.contacts.all

        @state_changes = entity_check.states.intersect(nil, Time.now.to_i,
                           :order => 'desc', :limit => 20)

        erb 'check.html'.to_sym
      end

      post '/acknowledgements/:entity/:check' do
        @entity             = params[:entity]
        @check              = params[:check]
        @summary            = params[:summary]
        @acknowledgement_id = params[:acknowledgement_id]

        dur = ChronicDuration.parse(params[:duration] || '')
        @duration = (dur.nil? || (dur <= 0)) ? (4 * 60 * 60) : dur

        entity_check = Flapjack::Data::EntityCheckR.intersect(:entity_name => @entity,
          :name => @check).all.first
        return 404 if entity_check.nil?

        ack = Flapjack::Data::Event.create_acknowledgement(
          config['processor_queue'] || 'events',
          @entity, @check,
          :summary => (@summary || ''),
          :acknowledgement_id => @acknowledgement_id,
          :duration => @duration,
        )

        redirect back
      end

      # FIXME: there is bound to be a more idiomatic / restful way of doing this
      # (probably using 'delete' or 'patch')
      post '/end_unscheduled_maintenance/:entity/:check' do
        @entity = params[:entity]
        @check  = params[:check]

        entity_check = Flapjack::Data::EntityCheckR.intersect(:entity_name => @entity,
          :name => @check).all.first
        return 404 if entity_check.nil?

        entity_check.end_unscheduled_maintenance(Time.now.to_i)

        redirect back
      end

      # create scheduled maintenance
      post '/scheduled_maintenances/:entity/:check' do
        start_time = Chronic.parse(params[:start_time]).to_i
        raise ArgumentError, "start time parsed to zero" unless start_time > 0
        duration   = ChronicDuration.parse(params[:duration])
        summary    = params[:summary]

        entity_check = Flapjack::Data::EntityCheckR.intersect(:entity_name => @entity,
          :name => @check).all.first
        return 404 if entity_check.nil?

        sched_maint = Flapjack::Data::ScheduledMaintenanceR.new(:start_time => start_time,
          :end_time => start_time + duration, :summary => summary)
        sched_maint.save
        entity_check.add_scheduled_maintenance(sched_maint)

        redirect back
      end

      # delete a scheduled maintenance
      delete '/scheduled_maintenances/:entity/:check' do
        entity_check = Flapjack::Data::EntityCheckR.intersect(:entity_name => @entity,
          :name => @check).all.first
        return 404 if entity_check.nil?

        # TODO better error checking on this param?
        start_time = params[:start_time].to_i

        sched_maint = entity_check.scheduled_maintenances_by_start.
          intersect_range(start_time, start_time, :by_score => true).all.first
        return 404 if sched_maint.nil?

        entity_check.end_scheduled_maintenance(sched_maint, Time.now.to_i)
        redirect back
      end

      # delete a check (actually just disables it)
      delete '/checks/:entity/:check' do
        entity_check = Flapjack::Data::EntityCheckR.intersect(:entity_name => @entity,
          :name => @check).all.first
        return 404 if entity_check.nil?

        entity_check.enabled = false
        entity_check.save

        redirect back
      end

      get '/contacts' do
        @contacts = Flapjack::Data::ContactR.all

        erb 'contacts.html'.to_sym
      end

      get "/contacts/:contact" do
        if contact_id = params[:contact]
          @contact = Flapjack::Data::ContactR.find_by_id(contact_id)
        end
        return 404 if @contact.nil?

        media = @contact.media.all

        if media.any? {|m| m.type == 'pagerduty'}
          @pagerduty_credentials = @contact.pagerduty_credentials
        end

        erb 'contact.html'.to_sym
      end

    protected

      # TODO cache constructed erb object to improve performance -- check mtime
      # to know when to refresh; would need to synchronize accesses to the cache,
      # to lock out reads while it's being refreshed
      def render_erb(file, bind)
        erb = ERB.new(File.read(File.dirname(__FILE__) + '/web/views/' + file))
        erb.result(bind)
      end

    private

      def entity_check_state(entity_check)
        summary = entity_check.summary
        summary = summary[0..76] + '...' unless summary.nil? || (summary.length < 81)

        latest_problem  = entity_check.notifications.intersect(:state => 'problem').last
        latest_recovery = entity_check.notifications.intersect(:state => 'recovery').last
        latest_ack      = entity_check.notifications.intersect(:state => 'acknowledgement').last

        latest_notif =
          {:problem         => (latest_problem  ? latest_problem.timestamp  : nil),
           :recovery        => (latest_recovery ? latest_recovery.timestamp : nil),
           :acknowledgement => (latest_ack      ? latest_ack.timestamp      : nil),
          }.max_by {|n| n[1] || 0}

        lc = entity_check.last_change
        last_change   = lc ? ChronicDuration.output(Time.now.to_i - lc.timestamp.to_i,
                               :format => :short, :keep_zero => true, :units => 2) : 'never'

        lu = entity_check.last_update
        last_update   = lu ? ChronicDuration.output(Time.now.to_i - lu.timestamp.to_i,
                               :format => :short, :keep_zero => true, :units => 2) : 'never'

        ln = latest_notif[1]
        last_notified = ln ? ChronicDuration.output(Time.now.to_i - ln.timestamp.to_i,
                               :format => :short, :keep_zero => true, :units => 2) + ", #{latest_notif[0]}" : 'never'

        [(entity_check.state       || '-'),
         (summary                  || '-'),
         last_change,
         last_update,
         entity_check.in_unscheduled_maintenance?,
         entity_check.in_scheduled_maintenance?,
         last_notified
        ]
      end

      def self_stats
        @fqdn         = `/bin/hostname -f`.chomp
        @pid          = Process.pid
        @instance_id  = "#{@fqdn}:#{@pid}"

        @dbsize                  = Flapjack.redis.dbsize
        @executive_instances     = Flapjack.redis.keys("executive_instance:*").map {|i|
          [ i.match(/executive_instance:(.*)/)[1], Flapjack.redis.hget(i, 'boot_time').to_i ]
        }.sort {|a, b| b[1] <=> a[1]}
        @event_counters          = Flapjack.redis.hgetall('event_counters')
        @event_counters_instance = Flapjack.redis.hgetall("event_counters:#{@instance_id}")
        @boot_time               = Time.at(Flapjack.redis.hget("executive_instance:#{@instance_id}", 'boot_time').to_i)
        @uptime                  = Time.now.to_i - @boot_time.to_i
        @uptime_string           = time_period_in_words(@uptime)
        @event_rate_all          = (@uptime > 0) ?
                                   (@event_counters_instance['all'].to_f / @uptime) : 0
        @events_queued           = Flapjack.redis.llen('events')
      end

      def entity_stats
        @count_all_entities      = Flapjack::Data::EntityR.intersect(:enabled => true).count
        @count_failing_entities  = Flapjack::Data::EntityCheckR.hash_by_entity_name(
          Flapjack::Data::EntityCheckR.union(:state =>
            Flapjack::Data::CheckStateR.failing_states.collect)).keys.size
      end

      def check_stats
        @count_all_checks        = Flapjack::Data::EntityCheckR.count
        @count_failing_checks    = Flapjack::Data::EntityCheckR.union(:state =>
          Flapjack::Data::CheckStateR.failing_states.collect).count
      end

      def last_notification_data(entity_check)
        last_notifications = entity_check.last_notifications_of_each_type
        [:critical, :warning, :unknown, :recovery, :acknowledgement].inject({}) do |memo, type|
          if last_notifications[type] && last_notifications[type].timestamp
            t = Time.at(last_notifications[type].timestamp)
            memo[type] = {:time => t.to_s,
                          :relative => relative_time_ago(t) + " ago",
                          :summary => last_notifications[type].summary}
          end
          memo
        end
      end

    end

  end

end
