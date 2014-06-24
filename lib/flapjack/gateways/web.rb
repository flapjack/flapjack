#!/usr/bin/env ruby

require 'chronic'
require 'chronic_duration'
require 'sinatra/base'
require 'erb'
require 'rack/fiber_pool'
require 'json'
require 'uri'

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
          @redis = Flapjack::RedisPool.new(:config => @redis_config, :size => 2)

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

          @base_url = @config['base_url']
          if @base_url
            @base_url = $1 if @base_url.match(/^(.+\/)$/)
          else
	          dummy_url = "/"
            @logger.error "base_url must contain trailing '/', setting it to safe default (#{dummy_url})"
            @base_url = dummy_url
          end

          # constants won't be exposed to eRb scope
          @default_logo_url = "img/flapjack-2013-notext-transparent-300-300.png"
          @logo_image_file  = nil
          @logo_image_ext   = nil

          if logo_image_path = @config['logo_image_path']
            if File.file?(logo_image_path)
              @logo_image_file = logo_image_path
              @logo_image_ext  = File.extname(logo_image_path)
            else
              @logger.error "logo_image_path '#{logo_image_path}'' does not point to a valid file."
            end
          end
        end
      end

      include Flapjack::Utility

      set :protection, :except => :path_traversal

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
          request.path == "/#{path}" ? " class='active'" : ""
        end
      end

      def redis
        self.class.instance_variable_get('@redis')
      end

      def logger
        self.class.instance_variable_get('@logger')
      end

      before do
        @api_url          = self.class.instance_variable_get('@api_url')
        @base_url         = self.class.instance_variable_get('@base_url')
        @default_logo_url = self.class.instance_variable_get('@default_logo_url')
        @logo_image_file  = self.class.instance_variable_get('@logo_image_file')
        @logo_image_ext   = self.class.instance_variable_get('@logo_image_ext')
      end

      get '/img/branding.*' do
        halt(404) unless @logo_image_file && params[:splat].first.eql?(@logo_image_ext[1..-1])
        send_file(@logo_image_file)
      end

      get '/' do
        check_stats
        entity_stats

        erb 'index.html'.to_sym
      end

      get '/checks_all' do
        check_stats
        @adjective = 'all'

        checks_by_entity = Flapjack::Data::EntityCheck.find_all_by_entity(:redis => redis)
        @states = checks_by_entity.keys.inject({}) {|result, entity|
          result[entity] = checks_by_entity[entity].sort.map {|check|
            [check] + entity_check_state(entity, check)
          }
          result
        }
        @entities_sorted = checks_by_entity.keys.sort

        erb 'checks.html'.to_sym
      end

      get '/checks_failing' do
        check_stats
        @adjective = 'failing'

        checks_by_entity = Flapjack::Data::EntityCheck.find_all_failing_by_entity(:redis => redis)
        @states = checks_by_entity.keys.inject({}) {|result, entity|
          result[entity] = checks_by_entity[entity].sort.map {|check|
            [check] + entity_check_state(entity, check)
          }
          result
        }
        @entities_sorted = checks_by_entity.keys.sort

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
        @entities = Flapjack::Data::Entity.find_all_with_checks(:redis => redis)

        erb 'entities.html'.to_sym
      end

      get '/entities_failing' do
        entity_stats
        @adjective = 'failing'
        @entities = Flapjack::Data::Entity.find_all_with_failing_checks(:redis => redis)

        erb 'entities.html'.to_sym
      end

      get '/entity/:entity' do
        @entity = params[:entity]
        entity_stats
        @states = Flapjack::Data::EntityCheck.find_all_for_entity_name(@entity, :redis => redis).sort.map { |check|
          [check] + entity_check_state(@entity, check)
        }.sort_by {|parts| parts }

        erb 'entity.html'.to_sym
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
        @check_perfdata             = entity_check.perfdata

        @last_notifications         = last_notification_data(entity_check)

        @scheduled_maintenances     = entity_check.maintenances(nil, nil, :scheduled => true)
        @acknowledgement_id         = entity_check.failed? ? entity_check.ack_hash : nil

        @current_scheduled_maintenance   = entity_check.current_maintenance(:scheduled => true)
        @current_unscheduled_maintenance = entity_check.current_maintenance(:scheduled => false)

        @contacts                   = entity_check.contacts

        @state_changes = entity_check.historical_states(nil, Time.now.to_i,
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

        entity_check.end_unscheduled_maintenance(Time.now.to_i)

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

        entity_check.create_scheduled_maintenance(start_time, duration,
                                                  :summary => summary)
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
        @contacts = Flapjack::Data::Contact.all(:redis => redis)

        erb 'contacts.html'.to_sym
      end

      get '/edit_contacts' do
        erb 'edit_contacts.html'.to_sym
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

        # FIXME: intersect with current checks, or push down to Contact.entities
        @entities_and_checks = @contact.entities(:checks => true).sort_by {|ec|
          ec[:entity].name
        }

        erb 'contact.html'.to_sym
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
        return ['-', '-', 'never', 'never', false, false, 'never'] if entity.nil?
        entity_check = Flapjack::Data::EntityCheck.for_entity(entity,
          check, :redis => redis)
        summary = entity_check.summary
        summary = summary[0..76] + '...' unless (summary.nil? || (summary.length < 81))
        latest_notif =
          {:problem         => entity_check.last_notification_for_state(:problem)[:timestamp],
           :recovery        => entity_check.last_notification_for_state(:recovery)[:timestamp],
           :acknowledgement => entity_check.last_notification_for_state(:acknowledgement)[:timestamp]
          }.max_by {|n| n[1] || 0}

        lc = entity_check.last_change
        last_change   = lc ? (ChronicDuration.output(Time.now.to_i - lc.to_i,
                               :format => :short, :keep_zero => true, :units => 2) || '0s') : 'never'

        lu = entity_check.last_update
        last_update   = lu ? (ChronicDuration.output(Time.now.to_i - lu.to_i,
                               :format => :short, :keep_zero => true, :units => 2) || '0s') : 'never'

        ln = latest_notif[1]
        last_notified = ln ? (ChronicDuration.output(Time.now.to_i - ln.to_i,
                               :format => :short, :keep_zero => true, :units => 2) || '0s') + ", #{latest_notif[0]}" : 'never'

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
        @fqdn    = `/bin/hostname -f`.chomp
        @pid     = Process.pid

        @dbsize              = redis.dbsize
        @executive_instances = redis.keys("executive_instance:*").inject({}) do |memo, i|
          instance_id    = i.match(/executive_instance:(.*)/)[1]
          boot_time      = redis.hget(i, 'boot_time').to_i
          uptime         = Time.now.to_i - boot_time
          uptime_string  = (ChronicDuration.output(uptime, :format => :short, :keep_zero => true, :units => 2) || '0s')
          event_counters = redis.hgetall("event_counters:#{instance_id}")
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
        @event_counters = redis.hgetall('event_counters')
        @events_queued  = redis.llen('events')
        @current_checks_ages = Flapjack::Data::EntityCheck.find_all_split_by_freshness([0, 60, 300, 900, 3600], {:redis => redis, :counts => true } )
      end

      def entity_stats
        @count_all_entities      = Flapjack::Data::Entity.find_all_with_checks(:redis => redis).length
        @count_failing_entities  = Flapjack::Data::Entity.find_all_with_failing_checks(:redis => redis).length
      end

      def check_stats
        # FIXME: move this logic to Flapjack::Data::EntityCheck
        @count_all_checks        = Flapjack::Data::EntityCheck.count_all(:redis => redis)
        @count_failing_checks    = Flapjack::Data::EntityCheck.count_all_failing(:redis => redis)
      end

      def last_notification_data(entity_check)
        last_notifications = entity_check.last_notifications_of_each_type
        [:critical, :warning, :unknown, :recovery, :acknowledgement].inject({}) do |memo, type|
          if last_notifications[type] && last_notifications[type][:timestamp]
            t = Time.at(last_notifications[type][:timestamp])
            memo[type] = {:time => t.to_s,
                          :relative => relative_time_ago(t) + " ago",
                          :summary => last_notifications[type][:summary]}
          end
          memo
        end
      end

      def require_css(*css)
        @required_css ||= []
        @required_css += css
      end

      def require_js(*js)
        @required_js ||= []
        @required_js += js
        @required_js.uniq!
      end

      def include_required_js
        if @required_js
          @required_js.map { |filename|
            "<script type='text/javascript' src='#{link_to("js/#{filename}.js")}'></script>"
          }.join("\n    ")
        else
          ""
        end
      end

      def include_required_css
        if @required_css
          @required_css.map { |filename|
            %(<link rel="stylesheet" href="#{link_to("css/#{filename}.css")}" media="screen">)
          }.join("\n    ")
        else
          ""
        end
      end

      # from http://gist.github.com/98310
      def link_to(url_fragment, mode=:path_only)
        case mode
        when :path_only
          base = @base_url
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
