#!/usr/bin/env ruby

require 'chronic'
require 'chronic_duration'
require 'sinatra/base'
require 'erb'

require 'flapjack'

require 'flapjack/data/contact'
require 'flapjack/data/check'
require 'flapjack/data/event'
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
        time = Time.now

        checks_by_entity = Flapjack::Data::Check.hash_by_entity_name( Flapjack::Data::Check.all )
        @entities_sorted = checks_by_entity.keys.sort
        @states = checks_by_entity.inject({}) {|result, (entity_name, checks)|
          result[entity_name] = checks.sort_by(&:name).map {|entity_check|
            [entity_check.name] + entity_check_state(entity_check, time)
          }
          result
        }

        erb 'checks.html'.to_sym
      end

      get '/checks_failing' do
        check_stats
        @adjective = 'failing'
        time = Time.now

        checks_by_entity = Flapjack::Data::Check.hash_by_entity_name( failing_checks.all )
        @entities_sorted = checks_by_entity.keys.sort
        @states = checks_by_entity.inject({}) {|result, (entity_name, checks)|
          result[entity_name] = checks.sort_by(&:name).map {|entity_check|
            [entity_check.name] + entity_check_state(entity_check, time)
          }
          result
        }

        erb 'checks.html'.to_sym
      end

      get '/self_stats' do
        @current_time = Time.now

        self_stats(@current_time)
        entity_stats
        check_stats

        erb 'self_stats.html'.to_sym
      end

      get '/self_stats.json' do
        time = Time.now

        self_stats(time)
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
          'current_time' => time,
          'executive_instances' => @executive_instances,
        }.to_json
      end

      get '/entities_all' do
        entity_stats
        @adjective = 'all'
        @entities = Flapjack::Data::Entity.intersect(:enabled => true).all.
          map(&:name).sort

        erb 'entities.html'.to_sym
      end

      get '/entities_failing' do
        entity_stats
        @adjective = 'failing'
        failing_checks = Flapjack::Data::Check.
          union(:state => Flapjack::Data::CheckState.failing_states).all

        checks_by_entity = Flapjack::Data::Check.hash_by_entity_name( failing_checks )

        @entities = checks_by_entity.keys.sort

        erb 'entities.html'.to_sym
      end

      get '/entity/:entity' do
        @entity = params[:entity]
        entity_stats
        time = Time.now

        @states = Flapjack::Data::Check.
          intersect(:entity_name => @entity).all.sort_by(&:name).map { |entity_check|
          [entity_check.name] + entity_check_state(entity_check, time)
        }.sort_by {|parts| parts }

        erb 'entity.html'.to_sym
      end

      get '/check' do
        @entity = params[:entity]
        @check  = params[:check]

        @current_time = Time.now

        entity_check = Flapjack::Data::Check.intersect(:entity_name => @entity,
          :name => @check).all.first
        return 404 if entity_check.nil?

        check_stats
        states = entity_check.states

        last_change = states.last
        last_update = entity_check.last_update

        @check_state                = entity_check.state
        @check_enabled              = !!entity_check.enabled
        @check_last_update          = last_update
        @check_last_change          = last_change ? last_change.timestamp : nil
        @check_summary              = entity_check.summary
        @check_details              = entity_check.details

        @last_notifications         = last_notification_data(entity_check, @current_time)

        @scheduled_maintenances     = entity_check.scheduled_maintenances_by_start.all
        @acknowledgement_id         = entity_check.failed? ? entity_check.count : nil

        @current_scheduled_maintenance   = entity_check.current_scheduled_maintenance
        @current_unscheduled_maintenance = entity_check.current_unscheduled_maintenance

        @contacts                   = entity_check.contacts.all

        @state_changes = states.intersect_range(nil, @current_time.to_i,
                           :order => 'desc', :limit => 20).all

        erb 'check.html'.to_sym
      end

      post '/acknowledgements/:entity/:check' do
        @entity             = params[:entity]
        @check              = params[:check]
        @summary            = params[:summary]
        @acknowledgement_id = params[:acknowledgement_id]

        dur = ChronicDuration.parse(params[:duration] || '')
        @duration = (dur.nil? || (dur <= 0)) ? (4 * 60 * 60) : dur

        entity_check = Flapjack::Data::Check.intersect(:entity_name => @entity,
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

        entity_check = Flapjack::Data::Check.intersect(:entity_name => @entity,
          :name => @check).all.first
        return 404 if entity_check.nil?

        entity_check.end_unscheduled_maintenance(Time.now.to_i)

        redirect back
      end

      # create scheduled maintenance
      post '/scheduled_maintenances/:entity/:check' do
        @entity = params[:entity]
        @check  = params[:check]

        start_time = Chronic.parse(params[:start_time]).to_i
        raise ArgumentError, "start time parsed to zero" unless start_time > 0
        duration   = ChronicDuration.parse(params[:duration])
        summary    = params[:summary]

        entity_check = Flapjack::Data::Check.intersect(:entity_name => @entity,
          :name => @check).all.first
        return 404 if entity_check.nil?

        sched_maint = Flapjack::Data::ScheduledMaintenance.new(:start_time => start_time,
          :end_time => start_time + duration, :summary => summary)
        sched_maint.save
        entity_check.add_scheduled_maintenance(sched_maint)

        redirect back
      end

      # delete a scheduled maintenance
      delete '/scheduled_maintenances/:entity/:check' do
        @entity = params[:entity]
        @check  = params[:check]

        entity_check = Flapjack::Data::Check.intersect(:entity_name => @entity,
          :name => @check).all.first
        return 404 if entity_check.nil?

        # TODO better error checking on this param?
        start_time = params[:start_time].to_i

        sched_maint = entity_check.scheduled_maintenances_by_start.
          intersect_range(start_time, start_time, :by_score => true).first
        return 404 if sched_maint.nil?

        entity_check.end_scheduled_maintenance(sched_maint, Time.now.to_i)
        redirect back
      end

      # delete a check (actually just disables it)
      delete '/checks/:entity/:check' do
        entity_check = Flapjack::Data::Check.intersect(:entity_name => @entity,
          :name => @check).all.first
        return 404 if entity_check.nil?

        entity_check.enabled = false
        entity_check.save

        redirect back
      end

      get '/contacts' do
        @contacts = Flapjack::Data::Contact.all

        erb 'contacts.html'.to_sym
      end

      get "/contacts/:contact" do
        if contact_id = params[:contact]
          @contact = Flapjack::Data::Contact.find_by_id(contact_id)
        end
        return 404 if @contact.nil?

        @contact_media = @contact.media.all

        if @contact_media.any? {|m| m.type == 'pagerduty'}
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

      def entity_check_state(entity_check, time)
        summary = entity_check.summary
        summary = summary[0..76] + '...' unless summary.nil? || (summary.length < 81)

        latest_problem  = entity_check.states.
          union(:state => Flapjack::Data::CheckState.failing_states).
          intersect(:notified => true).last

        latest_recovery = entity_check.states.
          intersect(:state => 'ok', :notified => true).last

        latest_ack      = entity_check.states.
          intersect(:state => 'acknowledgement', :notified => true).last

        latest_notif =
          {:problem         => (latest_problem  ? latest_problem.timestamp  : nil),
           :recovery        => (latest_recovery ? latest_recovery.timestamp : nil),
           :acknowledgement => (latest_ack      ? latest_ack.timestamp      : nil),
          }.max_by {|n| n[1] || 0}

        lc = entity_check.states.last
        last_change   = lc ? ChronicDuration.output(time.to_i - lc.timestamp.to_i,
                               :format => :short, :keep_zero => true, :units => 2) : 'never'

        lu = entity_check.last_update
        last_update   = lu ? ChronicDuration.output(time.to_i - lu.to_i,
                               :format => :short, :keep_zero => true, :units => 2) : 'never'

        ln = latest_notif[1]
        last_notified = ln ? ChronicDuration.output(time.to_i - ln.to_i,
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

      def self_stats(time)
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
        @uptime                  = time.to_i - @boot_time.to_i
        @uptime_string           = time_period_in_words(@uptime)
        @event_rate_all          = (@uptime > 0) ?
                                   (@event_counters_instance['all'].to_f / @uptime) : 0
        @events_queued           = Flapjack.redis.llen('events')
      end

      def failing_checks
        @failing_checks ||= Flapjack::Data::Check.union(:state =>
                              Flapjack::Data::CheckState.failing_states)
      end

      def entity_stats
        @count_all_entities      = Flapjack::Data::Entity.intersect(:enabled => true).count
        failing_enabled_checks   = failing_checks.intersect(:enabled => true).all
        @count_failing_entities  = Flapjack::Data::Check.hash_by_entity_name(
          failing_enabled_checks).keys.size
      end

      def check_stats
        @count_all_checks        = Flapjack::Data::Check.count
        @count_failing_checks    = failing_checks.count
      end

      def last_notification_data(entity_check, time)
        states = entity_check.states
        ['critical', 'warning', 'unknown', 'recovery', 'acknowledgement'].inject({}) do |memo, type|
          state = (type == 'recovery') ? 'ok' : type
          notif = states.intersect(:state => state, :notified => true).last
          next memo if (notif.nil? || notif.timestamp.nil?)
          t = Time.at(notif.timestamp)
          memo[type.to_sym] = {:time => t.to_s,
                               :relative => relative_time_ago(time, t) + " ago",
                               :summary => notif.summary}
          memo
        end
      end

    end

  end

end
