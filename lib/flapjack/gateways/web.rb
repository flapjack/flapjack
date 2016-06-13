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
        if @config['show_exceptions'].is_a?(TrueClass)
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
          @redis = Flapjack::RedisPool.new(:config => @redis_config, :size => 2, :logger => @logger)

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
            if URI.regexp(['http', 'https']).match(@api_url).nil?
              @logger.error "api_url is not a valid http or https URI (#{@api_url}), discarding"
              @api_url = nil
            end
            unless @api_url.match(/^.*\/$/)
              @logger.info "api_url must end with a trailing '/', setting to '#{@api_url}/'"
              @api_url = "#{@api_url}/"
            end
          end

          unless @api_url
            @logger.error "api_url is not configured, parts of the web interface will be broken"
          end

          @base_url = @config['base_url']
          unless @base_url
            @logger.info "base_url is not configured, setting to '/'"
            @base_url = '/'
          end

          unless @base_url.match(/^.*\/$/)
            @logger.warn "base_url must end with a trailing '/', setting to '#{@base_url}/'"
            @base_url = "#{@base_url}/"
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

          @auto_refresh = @config['auto_refresh'].respond_to?('to_i') && @config['auto_refresh'].to_i > 0 ? @config['auto_refresh'].to_i : false
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

        def charset_for_content_type(ct)
          charset = Encoding.default_external
          charset.nil? ? ct : "#{ct}; charset=#{charset}"
        end
      end

      def redis
        self.class.instance_variable_get('@redis')
      end

      def logger
        self.class.instance_variable_get('@logger')
      end

      before do
        content_type charset_for_content_type('text/html')

        @api_url          = self.class.instance_variable_get('@api_url')
        @base_url         = self.class.instance_variable_get('@base_url')
        @default_logo_url = self.class.instance_variable_get('@default_logo_url')
        @logo_image_file  = self.class.instance_variable_get('@logo_image_file')
        @logo_image_ext   = self.class.instance_variable_get('@logo_image_ext')
        @auto_refresh     = self.class.instance_variable_get('@auto_refresh')

        input = nil
        query_string = (request.query_string.respond_to?(:length) &&
                        request.query_string.length > 0) ? "?#{request.query_string}" : ""
        if logger.debug?
          input = env['rack.input'].read
          logger.debug("#{request.request_method} #{request.path_info}#{query_string} #{input}")
        elsif logger.info?
          input = env['rack.input'].read
          input_short = input.gsub(/\n/, '').gsub(/\s+/, ' ')
          logger.info("#{request.request_method} #{request.path_info}#{query_string} #{input_short[0..80]}")
        end
        env['rack.input'].rewind unless input.nil?
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
        @adjective = ''

        checks_by_entity = Flapjack::Data::EntityCheck.find_current_names_by_entity(:redis => redis)
        @states = checks_by_entity.keys.inject({}) {|result, entity_name|
          Flapjack::Data::Entity.find_by_name(entity_name, :redis => redis, :create => true)
          result[entity_name] = checks_by_entity[entity_name].sort.map {|check|
            [check] + entity_check_state(entity_name, check)
          }
          result
        }
        @entities_sorted = checks_by_entity.keys.sort

        erb 'checks.html'.to_sym
      end

      get '/checks_failing' do
        check_stats
        @adjective = 'failing'

        checks_by_entity = Flapjack::Data::EntityCheck.find_current_names_failing_by_entity(:redis => redis)
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
        logger.debug "calculating self_stats"
        self_stats
        logger.debug "calculating entity_stats"
        entity_stats
        logger.debug "calculating check_stats"
        check_stats

        erb 'self_stats.html'.to_sym
      end

      get '/self_stats.json' do
        self_stats
        entity_stats
        check_stats
        json_data = {
          'events_queued'       => @events_queued,
          'all_entities'        => @count_current_entities,
          'failing_entities'    => @count_failing_entities,
          'all_checks'          => @count_current_checks,
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
        }
        Flapjack.dump_json(json_data)
      end

      get '/entities_all' do
        redirect '/entities'
      end

      get '/entities' do
        @entities = Flapjack::Data::Entity.all(:enabled => true, :redis => redis).map {|e| e.name}

        entity_stats(@entities)
        @adjective = ''

        erb 'entities.html'.to_sym
      end

      get '/entities_decommissioned' do
        entity_stats
        @adjective = 'decommissioned'
        @entities = Flapjack::Data::Entity.all(:enabled => false, :redis => redis)

        erb 'entities.html'.to_sym
      end

      get '/entities_failing' do
        entity_stats
        @adjective = 'failing'
        @entities = Flapjack::Data::Entity.find_all_names_with_failing_checks(:redis => redis)

        erb 'entities.html'.to_sym
      end

      get '/entity/:entity' do
        @entity = params[:entity]
        entity_stats
        @states = Flapjack::Data::EntityCheck.find_current_names_for_entity_name(@entity, :redis => redis).sort.map { |check|
          [check] + entity_check_state(@entity, check)
        }.sort_by {|parts| parts }

        erb 'entity.html'.to_sym
      end

      get '/check' do

        @entity = params[:entity]
        @check  = params[:check]

        entity_check = get_entity_check(@entity, @check)
        halt(404, "Could not find check '#{@entity}:#{@check}'") if entity_check.nil?

        last_change = entity_check.last_change

        @check_state                = entity_check.state
        @check_enabled              = entity_check.enabled?
        @check_last_update          = entity_check.last_update
        @check_last_change          = last_change
        @check_summary              = entity_check.summary
        @check_details              = entity_check.details
        @check_perfdata             = entity_check.perfdata

        @check_initial_failure_delay = entity_check.initial_failure_delay ||
          Flapjack::DEFAULT_INITIAL_FAILURE_DELAY
        @check_repeat_failure_delay  = entity_check.repeat_failure_delay  ||
          Flapjack::DEFAULT_REPEAT_FAILURE_DELAY
        @check_initial_recovery_delay = entity_check.initial_recovery_delay ||
          Flapjack::DEFAULT_INITIAL_RECOVERY_DELAY

        @check_initial_failure_delay_is_default = entity_check.initial_failure_delay   ? false : true
        @check_repeat_failure_delay_is_default  = entity_check.repeat_failure_delay    ? false : true
        @check_initial_recovery_delay_is_default = entity_check.initial_recovery_delay ? false : true

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

        entity_check = get_entity_check(@entity, @check)
        halt(404, "Could not find check '#{@entity}:#{@check}'") if entity_check.nil?

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
        halt(404, "Could not find check '#{@entity}:#{@check}'") if entity_check.nil?

        entity_check.end_unscheduled_maintenance(Time.now.to_i)

        redirect back
      end

      # create scheduled maintenance for an entity
      post '/scheduled_maintenances/:entity' do
        start_time = Chronic.parse(params[:start_time]).to_i
        halt(400, "Start time '#{params[:start_time]}' parsed to 0") if start_time == 0
        duration   = ChronicDuration.parse(params[:duration])
        summary    = params[:summary]
        
        entity = get_entity(params[:entity])
        halt(404, "Could not find entity '#{params[:entity]}'") if entity.nil?

        checks = entity.check_list
        checks.each do | check |          
          entity_check = get_entity_check(params[:entity], check)
          halt(404, "Could not find check '#{params[:entity]}:#{check}'") if entity_check.nil?

          entity_check.create_scheduled_maintenance(start_time, duration,
                                                  :summary => summary)
        end

        redirect back
      end

      # create scheduled maintenance
      post '/scheduled_maintenances/:entity/:check' do
        start_time = Chronic.parse(params[:start_time]).to_i
        halt(400, "Start time '#{params[:start_time]}' parsed to 0") if start_time == 0
        duration   = ChronicDuration.parse(params[:duration])
        summary    = params[:summary]

        entity_check = get_entity_check(params[:entity], params[:check])
        halt(404, "Could not find check '#{params[:entity]}:#{params[:check]}'") if entity_check.nil?

        entity_check.create_scheduled_maintenance(start_time, duration,
                                                  :summary => summary)
        redirect back
      end

      # delete a scheduled maintenance
      delete '/scheduled_maintenances/:entity/:check' do
        entity_check = get_entity_check(params[:entity], params[:check])
        halt(404, "Could not find check '#{params[:entity]}:#{params[:check]}'") if entity_check.nil?

        entity_check.end_scheduled_maintenance(params[:start_time].to_i)
        redirect back
      end

      # delete a scheduled maintenance for an entity
      delete '/scheduled_maintenances/:entity' do
        entity = get_entity(params[:entity])
        
        halt(404, "Could not find entity '#{params[:entity]}'") if entity.nil?

        entity.end_scheduled_maintenance(:redis => redis)
        redirect back
      end 

      # delete a check (actually just disables it)
      delete '/checks/:entity/:check' do
        entity_check = get_entity_check(params[:entity], params[:check])
        halt(404, "Could not find check '#{params[:entity]}:#{params[:check]}'") if entity_check.nil?

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
        halt(404, "No contact id") if contact_id.nil?

        @contact = Flapjack::Data::Contact.find_by_id(contact_id, :redis => redis)
        halt(404, "Could not find contact '#{contact_id}'") if @contact.nil?

        if @contact.media.has_key?('pagerduty')
          @pagerduty_credentials = @contact.pagerduty_credentials
        end

        # FIXME: intersect with current checks, or push down to Contact.entities
        @entities_and_checks = @contact.entities(:checks => true).
          select  {|cec| cec.key?(:entity) && !cec[:entity].nil? }.
          sort_by {|ec| ec[:entity].name }

        erb 'contact.html'.to_sym
      end

    private

      def get_entity_check(entity, check)
        entity_obj = (entity && entity.length > 0) ?
          Flapjack::Data::Entity.find_by_name(entity, :redis => redis) : nil
        return if entity_obj.nil? || (check.nil? || check.length == 0)
        Flapjack::Data::EntityCheck.for_entity(entity_obj, check, :redis => redis)
      end

      def get_entity(entity)
        entity_obj = (entity && entity.length > 0) ?
          Flapjack::Data::Entity.find_by_name(entity, :redis => redis) : nil
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
        @current_checks_ages = Flapjack::Data::EntityCheck.find_all_split_by_freshness([0, 60, 300, 900, 3600], {:redis => redis, :logger => logger, :counts => true } )
      end

      def entity_stats(entities = nil)
        @count_current_entities  = (entities || Flapjack::Data::Entity.all(:enabled => true, :redis => redis)).length
        @count_failing_entities  = Flapjack::Data::Entity.find_all_names_with_failing_checks(:redis => redis).length
      end

      def check_stats
        @count_current_checks    = Flapjack::Data::EntityCheck.count_current(:redis => redis)
        @count_failing_checks    = Flapjack::Data::EntityCheck.count_current_failing(:redis => redis)
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
