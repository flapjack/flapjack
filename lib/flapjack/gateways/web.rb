#!/usr/bin/env ruby

require 'chronic'
require 'chronic_duration'
require 'sinatra/base'
require 'erb'
require 'uri'

require 'flapjack/redis_proxy'

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

            @api_url = @config['api_url']
            if @api_url
              if (@api_url =~ /^#{URI::regexp(%w(http https))}$/).nil?
                @logger.error "api_url is not a valid http or https URI (#{@api_url})"
                @api_url = nil
              end
            end

            unless @api_url
              @logger.error "api_url is not configured, parts of the web interface will be broken"
            end
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

        def include_active?(path)
          return '' unless request.path == "/#{path}"
          " class='active'"
        end
      end

      ['logger', 'config'].each do |class_inst_var|
        define_method(class_inst_var.to_sym) do
          self.class.instance_variable_get("@#{class_inst_var}")
        end
      end

      def api_url
        self.class.instance_variable_get('@api_url')
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
        @entity_names_sorted = checks_by_entity.keys.sort
        @states = checks_by_entity.inject({}) {|result, (entity_name, checks)|
          result[entity_name] = checks.sort_by(&:name).map {|check|
            [check.name] + check_state(check, time)
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
        @entity_names_sorted = checks_by_entity.keys.sort
        @states = checks_by_entity.inject({}) {|result, (entity_name, checks)|
          result[entity_name] = checks.sort_by(&:name).map {|check|
            [check.name] + check_state(check, time)
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
          'events_queued'       => @events_queued,
          'all_entities'        => @count_all_entities,
          'failing_entities'    => @count_failing_entities,
          'all_checks'          => @count_all_checks,
          'failing_checks'      => @count_failing_checks,
          'processed_events' => {
            'all_time' => {
              'total'   => @event_counters['all'].to_i,
              'ok'      => @event_counters['ok'].to_i,
              'failure' => @event_counters['failure'].to_i,
              'action'  => @event_counters['action'].to_i,
            }
          },
          'check_freshness'     => @current_checks_ages,
          'total_keys'          => @dbsize,
          'uptime'              => @uptime_string,
          'boottime'            => @boot_time,
          'current_time'        => Time.now,
          'executive_instances' => @executive_instances,
        }.to_json
      end

      get '/entities_all' do
        entity_stats
        @adjective = 'all'
        @entity_names = Flapjack::Data::Entity.intersect(:enabled => true).all.
          map(&:name).sort

        erb 'entities.html'.to_sym
      end

      get '/entities_failing' do
        entity_stats
        @adjective = 'failing'
        failing_checks = Flapjack::Data::Check.
          intersect(:state => Flapjack::Data::CheckState.failing_states).all

        checks_by_entity = Flapjack::Data::Check.hash_by_entity_name( failing_checks )

        @entity_names = checks_by_entity.keys.sort

        erb 'entities.html'.to_sym
      end

      get '/entity/:entity' do
        @entity_name = params[:entity]
        entity_stats
        time = Time.now

        @states = Flapjack::Data::Check.intersect(:entity_name => @entity_name).
          all.sort_by(&:name).map {|check|
            [check.name] + check_state(check, time)
          }.sort_by {|parts| parts }

        erb 'entity.html'.to_sym
      end

      get '/check' do
        @entity_name = params[:entity]
        @check_name  = params[:check]

        @current_time = Time.now

        check = Flapjack::Data::Check.intersect(:entity_name => @entity_name,
          :name => @check_name).all.first
        return 404 if check.nil?

        check_stats
        states = check.states

        last_change = states.last
        last_update = check.last_update

        @check_state            = check.state
        @check_enabled          = !!check.enabled
        @check_last_update      = last_update
        @check_last_change      = last_change ? last_change.timestamp : nil
        @check_summary          = check.summary
        @check_details          = check.details
        @check_perfdata         = check.perfdata

        @last_notifications     = last_notification_data(check, @current_time)

        @scheduled_maintenances = check.scheduled_maintenances_by_start.all
        @acknowledgement_id     = Flapjack::Data::CheckState.failing_states.include?(check.state) ? check.ack_hash : nil

        @current_scheduled_maintenance   = check.scheduled_maintenance_at(@current_time)
        @current_unscheduled_maintenance = check.unscheduled_maintenance_at(@current_time)

        @contacts                   = check.contacts.all

        @state_changes = states.intersect_range(nil, @current_time.to_i,
                           :order => 'desc', :limit => 20, :by_score => true).all

        erb 'check.html'.to_sym
      end

      post '/acknowledgements/:entity/:check' do
        entity_name        = params[:entity]
        check_name         = params[:check]
        summary            = params[:summary]
        acknowledgement_id = params[:acknowledgement_id]

        dur = ChronicDuration.parse(params[:duration] || '')
        duration = (dur.nil? || (dur <= 0)) ? (4 * 60 * 60) : dur

        check = Flapjack::Data::Check.intersect(:entity_name => entity_name,
          :name => check_name).all.first
        return 404 if check.nil?

        ack = Flapjack::Data::Event.create_acknowledgement(
          config['processor_queue'] || 'events',
          check,
          :summary => (summary || ''),
          :acknowledgement_id => acknowledgement_id,
          :duration => duration,
        )

        redirect back
      end

      # FIXME: there is bound to be a more idiomatic / restful way of doing this
      # (probably using 'delete' or 'patch')
      post '/end_unscheduled_maintenance/:entity/:check' do
        entity_name = params[:entity]
        check_name  = params[:check]

        check = Flapjack::Data::Check.intersect(:entity_name => entity_name,
          :name => check_name).all.first
        return 404 if check.nil?

        check.end_unscheduled_maintenance(Time.now.to_i)

        redirect back
      end

      # create scheduled maintenance
      post '/scheduled_maintenances/:entity/:check' do
        entity_name = params[:entity]
        check_name  = params[:check]

        start_time = Chronic.parse(params[:start_time]).to_i
        raise ArgumentError, "start time parsed to zero" unless start_time > 0
        duration   = ChronicDuration.parse(params[:duration])
        summary    = params[:summary]

        check = Flapjack::Data::Check.intersect(:entity_name => entity_name,
          :name => check_name).all.first
        return 404 if check.nil?

        sched_maint = Flapjack::Data::ScheduledMaintenance.new(:start_time => start_time,
          :end_time => start_time + duration, :summary => summary)
        sched_maint.save
        check.add_scheduled_maintenance(sched_maint)

        redirect back
      end

      # delete a scheduled maintenance
      delete '/scheduled_maintenances/:entity/:check' do
        entity_name = params[:entity]
        check_name  = params[:check]

        check = Flapjack::Data::Check.intersect(:entity_name => entity_name,
          :name => check_name).all.first
        return 404 if check.nil?

        # TODO better error checking on this param?
        start_time = params[:start_time].to_i

        sched_maint = check.scheduled_maintenances_by_start.
          intersect_range(start_time, start_time, :by_score => true).first
        return 404 if sched_maint.nil?

        check.end_scheduled_maintenance(sched_maint, Time.now)
        redirect back
      end

      # delete a check (actually just disables it)
      delete '/checks/:entity/:check' do
        entity_name = params[:entity]
        check_name  = params[:check]

        check = Flapjack::Data::Check.intersect(:entity_name => entity_name,
          :name => check_name).all.first
        return 404 if check.nil?

        check.enabled = false
        check.save

        redirect back
      end

      get '/contacts' do
        @contacts = Flapjack::Data::Contact.all

        erb 'contacts.html'.to_sym
      end

      get '/edit_contacts' do
        @api_url = api_url
        erb 'edit_contacts.html'.to_sym
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

    private

      def check_state(check, time)
        summary = check.summary
        summary = summary[0..76] + '...' unless summary.nil? || (summary.length < 81)

        latest_problem  = check.states.
          intersect(:state => Flapjack::Data::CheckState.failing_states, :notified => true).last

        latest_recovery = check.states.
          intersect(:state => 'ok', :notified => true).last

        latest_ack      = check.states.
          intersect(:state => 'acknowledgement', :notified => true).last

        latest_notif =
          {:problem         => (latest_problem  ? latest_problem.timestamp  : nil),
           :recovery        => (latest_recovery ? latest_recovery.timestamp : nil),
           :acknowledgement => (latest_ack      ? latest_ack.timestamp      : nil),
          }.max_by {|n| n[1] || 0}

        lc = check.states.last
        last_change   = lc ? (ChronicDuration.output(time.to_i - lc.timestamp.to_i,
                               :format => :short, :keep_zero => true, :units => 2) || '0s') : 'never'

        lu = check.last_update
        last_update   = lu ? (ChronicDuration.output(time.to_i - lu.to_i,
                               :format => :short, :keep_zero => true, :units => 2) || '0s') : 'never'

        ln = latest_notif[1]
        last_notified = ln ? (ChronicDuration.output(time.to_i - ln.to_i,
                               :format => :short, :keep_zero => true, :units => 2) || '0s') + ", #{latest_notif[0]}" : 'never'

        [(check.state       || '-'),
         (summary           || '-'),
         last_change,
         last_update,
         check.in_unscheduled_maintenance?,
         check.in_scheduled_maintenance?,
         last_notified
        ]
      end

      def self_stats(time)
        @fqdn         = `/bin/hostname -f`.chomp
        @pid          = Process.pid
        @dbsize              = Flapjack.redis.dbsize
        @executive_instances = Flapjack.redis.keys("executive_instance:*").inject({}) do |memo, i|
          instance_id    = i.match(/executive_instance:(.*)/)[1]
          boot_time      = Flapjack.redis.hget(i, 'boot_time').to_i
          uptime         = Time.now.to_i - boot_time
          uptime_string  = (ChronicDuration.output(uptime, :format => :short, :keep_zero => true, :units => 2) || '0s')
          event_counters = Flapjack.redis.hgetall("event_counters:#{instance_id}")
          event_rates    = event_counters.inject({}) do |er, ec|
            er[ec[0]] = uptime && uptime > 0 ? (ec[1].to_f / uptime).round : nil
            er
          end
          memo[instance_id] = {
            'boot_time'      => boot_time,
            'uptime'         => uptime,
            'uptime_string'  => uptime_string,
            'event_counters' => event_counters,
            'event_rates'    => event_rates
          }
          memo
        end
        @event_counters = Flapjack.redis.hgetall('event_counters')
        @events_queued  = Flapjack.redis.llen('events')
        @current_checks_ages = Flapjack::Data::Check.split_by_freshness([0, 60, 300, 900, 3600], :counts => true)
      end

      def failing_checks
        @failing_checks ||= Flapjack::Data::Check.intersect(:state =>
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

      def last_notification_data(check, time)
        states = check.states
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

      def require_js(*js)
        @required_js ||= []
        @required_js += js
        @required_js.uniq!
      end

      def require_css(*css)
        @required_css ||= []
        @required_css += css
        @required_css.uniq!
      end

      def include_required_js
        return "" if @required_js.nil?
        @required_js.map { |filename|
          "<script type='text/javascript' src='#{link_to("/js/#{filename}.js")}'></script>"
        }.join("\n    ")
      end

      def include_required_css
        return "" if @required_css.nil?
        @required_css.map { |filename|
          %(<link rel="stylesheet" href="#{link_to("/css/#{filename}.css")}" media="screen">)
        }.join("\n    ")
      end

      # from http://gist.github.com/98310
      def link_to(url_fragment, mode=:path_only)
        case mode
        when :path_only
          base = request.script_name
        when :full_url
          if (request.scheme == 'http' && request.port == 80 ||
              request.scheme == 'https' && request.port == 443)
            port = ""
          else
            port = ":#{request.port}"
          end
          base = "#{request.scheme}://#{request.host}#{port}#{request.script_name}"
        else
          raise "Unknown script_url mode #{mode}"
        end
        "#{base}#{url_fragment}"
      end

      def page_title(string)
        @page_title = string
      end

      def include_page_title
        @page_title ? "#{@page_title} | Flapjack" : "Flapjack"
      end

    end

  end

end
