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
      set :protection, except: :path_traversal

      set :views, settings.root + '/web/views'
      set :public_folder, settings.root + '/web/public'

      use Rack::MethodOverride

      class << self
        def start
          Flapjack.logger.info "starting web - class"

          set :show_exceptions, @config['show_exceptions'].is_a?(TrueClass)

          if accesslog = (@config && @config['access_log'])
            if not File.directory?(File.dirname(accesslog))
              puts "Parent directory for log file #{accesslog} doesn't exist"
              puts "Exiting!"
              exit
            end

            use Rack::CommonLogger, ::Logger.new(@config['access_log'])
          end

          @api_url = @config['api_url']
           if @api_url
             if URI.regexp(['http', 'https']).match(@api_url).nil?
               Flapjack.logger.error "api_url is not a valid http or https URI (#{@api_url}), discarding"
               @api_url = nil
             end
             unless @api_url.match(/^.*\/$/)
               Flapjack.logger.info "api_url must end with a trailing '/', setting to '#{@api_url}/'"
               @api_url = "#{@api_url}/"
             end
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
              Flapjack.logger.error "logo_image_path '#{logo_image_path}'' does not point to a valid file."
            end
          end

          @auto_refresh = (@config['auto_refresh'].respond_to?('to_i') &&
                           (@config['auto_refresh'].to_i > 0)) ? @config['auto_refresh'].to_i : false
        end
      end

      include Flapjack::Utility

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

      ['config'].each do |class_inst_var|
        define_method(class_inst_var.to_sym) do
          self.class.instance_variable_get("@#{class_inst_var}")
        end
      end

      before do
        Sandstorm.redis ||= Flapjack.redis
        @api_url          = self.class.instance_variable_get('@api_url')
        @base_url         = "#{request.base_url}/"
        @default_logo_url = self.class.instance_variable_get('@default_logo_url')
        @logo_image_file  = self.class.instance_variable_get('@logo_image_file')
        @logo_image_ext   = self.class.instance_variable_get('@logo_image_ext')
        @auto_refresh     = self.class.instance_variable_get('@auto_refresh')

        input = nil
        query_string = (request.query_string.respond_to?(:length) &&
        request.query_string.length > 0) ? "?#{request.query_string}" : ""
        if Flapjack.logger.debug?
          input = env['rack.input'].read
          Flapjack.logger.debug("#{request.request_method} #{request.path_info}#{query_string} #{input}")
        elsif Flapjack.logger.info?
          input = env['rack.input'].read
          input_short = input.gsub(/\n/, '').gsub(/\s+/, ' ')
          Flapjack.logger.info("#{request.request_method} #{request.path_info}#{query_string} #{input_short[0..80]}")
        end
        env['rack.input'].rewind unless input.nil?
      end

      get '/img/branding.*' do
        halt(404) unless @logo_image_file && params[:splat].first.eql?(@logo_image_ext[1..-1])
        send_file(@logo_image_file)
       end

      get '/' do
        check_stats

        erb 'index.html'.to_sym
      end

      get '/self_stats' do
        @current_time = Time.now

        self_stats(@current_time)
        check_stats

        erb 'self_stats.html'.to_sym
      end

      get '/self_stats.json' do
        time = Time.now

        self_stats(time)
        check_stats
        Flapjack.dump_json({
          'events_queued'       => @events_queued,
          'enabled_checks'      => @count_enabled_checks,
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
        })
      end

      get '/checks' do
        check_stats
        time = Time.now

        @adjective, @checks = if 'failing'.eql?(params[:type])
          ['failing', failing_checks]
        else
          ['all', Flapjack::Data::Check.all]
        end

        @states = @checks.inject({}) do |memo, check|
          memo[check] = check_state(check, time)
          memo
        end

        erb 'checks.html'.to_sym
      end

      get '/checks/:id' do
        check_id  = params[:id]

        @current_time = Time.now

        @check = Flapjack::Data::Check.find_by_id(check_id)
        halt(404, "Could not find check '#{check_id}'") if @check.nil?

        check_stats

        last_change = @check.states.last
        last_update = @check.latest_notifications.last

        @check_enabled          = !!@check.enabled
        @check_last_change      = last_change ? last_change.timestamp : nil

        @check_state            = last_update ? last_update.condition : nil
        @check_last_update      = last_update ? last_update.timestamp : nil
        @check_summary          = last_update ? last_update.summary   : nil
        @check_details          = last_update ? last_update.details   : nil
        @check_perfdata         = last_update ? last_update.perfdata  : nil

        @last_notifications = @check.latest_notifications.all.each_with_object({}) do |entry, memo|
          t = Time.at(entry.timestamp)
          memo[(entry.action || entry.condition).to_sym] = {
            :time => t.to_s,
            :relative => relative_time_ago(@current_time, t) + " ago",
            :summary => entry.summary
          }
        end

        # @last_notifications[:acknowledgement] =
        #   @check.states.intersect(:action => 'acknowledgement',
        #                           :notified => true).last

        @last_notifications[:recovery] = @last_notifications.delete(:ok)

        @scheduled_maintenances = @check.scheduled_maintenances_by_start.all
        @acknowledgement_id = if Flapjack::Data::Condition.healthy?(@check_state)
          nil
        else
          @check.ack_hash
        end

        @current_scheduled_maintenance   = @check.scheduled_maintenance_at(@current_time)
        @current_unscheduled_maintenance = @check.unscheduled_maintenance_at(@current_time)

        Flapjack::Data::Contact.lock(Flapjack::Data::Medium, Flapjack::Data::Rule) do
          rule_ids_by_contact_id = @check.rule_ids_by_contact_id

          if rule_ids_by_contact_id.empty?
            @contacts = []
            @contact_media = {}
          else
            @contacts = Flapjack::Data::Contact.
              intersect(:id => rule_ids_by_contact_id.keys).sort(:name).all

            rule_ids = Set.new(rule_ids_by_contact_id.values.flatten)

            if rule_ids.empty?
              @contact_media = {}
            else

              media_ids_by_rule_id = Flapjack::Data::Rule.
                intersect(:id => rule_ids).associated_ids_for(:media)

              media_ids = Set.new(media_ids_by_rule_id.values.flatten)

              if media_ids.empty?
                @contact_media = {}
              else
                media_ids_by_contact_id = Flapjack::Data::Medium.
                  intersect(:id => media_ids).associated_ids_for(:contact)

                @contact_media = @contacts.each_with_object({}) do |contact, memo|
                  m_ids = media_ids_by_contact_id[contact.id]
                  next if m_ids.nil? || m_ids.empty?
                  memo[contact.id] = Flapjack::Data::Medium.intersect(:id => m_ids).all
                end
              end

            end

          end

        end

        @state_changes = @check.states.intersect_range(nil, @current_time.to_i,
                           :desc => true, :limit => 20, :by_score => true).all

        erb 'check.html'.to_sym
      end

      post "/unscheduled_maintenances/checks/:id" do
        check_id           = params[:id]
        summary            = params[:summary]
        acknowledgement_id = params[:acknowledgement_id]

        dur = ChronicDuration.parse(params[:duration] || '')
        duration = (dur.nil? || (dur <= 0)) ? (4 * 60 * 60) : dur

        check = Flapjack::Data::Check.find_by_id(check_id)
        halt(404, "Could not find check '#{check_id}'") if check.nil?

        ack = Flapjack::Data::Event.create_acknowledgements(
          config['processor_queue'] || 'events',
          [check],
          :summary => (summary || ''),
          :acknowledgement_id => acknowledgement_id,
          :duration => duration,
        )

        redirect back
      end

      patch '/unscheduled_maintenance/checks/:id' do
        check_id  = params[:id]

        check = Flapjack::Data::Check.find_by_id(check_id)
        halt(404, "Could not find check '#{check_id}'") if check.nil?

        check.end_unscheduled_maintenance(Time.now.to_i)

        redirect back
      end

      # create scheduled maintenance
      post '/scheduled_maintenances/checks/:id' do
        check_id  = params[:id]

        start_time = Chronic.parse(params[:start_time]).to_i
        raise ArgumentError, "start time parsed to zero" unless start_time > 0
        duration   = ChronicDuration.parse(params[:duration])
        summary    = params[:summary]

        check = Flapjack::Data::Check.find_by_id(check_id)
        halt(404, "Could not find check '#{check_id}'") if check.nil?

        sched_maint = Flapjack::Data::ScheduledMaintenance.new(:start_time => start_time,
          :end_time => start_time + duration, :summary => summary)
        sched_maint.save
        check.add_scheduled_maintenance(sched_maint)

        redirect back
      end

      # delete a scheduled maintenance
      delete '/scheduled_maintenances/checks/:id' do
        check_id  = params[:id]

        # TODO better error checking on this param?
        start_time = Time.parse(params[:start_time])

        check = Flapjack::Data::Check.find_by_id(check_id)
        halt(404, "Could not find check '#{check_id}'") if check.nil?

        # TODO maybe intersect_range should auto-coerce for timestamp fields?
        # (actually, this should just pass sched maint ID in now that it can)
        sched_maints = check.scheduled_maintenances_by_start.
          intersect_range(start_time.to_i, start_time.to_i, :by_score => true).all
        halt(404, "No scheduled maintenance periods found") if sched_maints.empty?

        sched_maints.each do |sched_maint|
          check.end_scheduled_maintenance(sched_maint, Time.now)
        end

        redirect back
      end

      get '/contacts' do
        @contacts = Flapjack::Data::Contact.all

        erb 'contacts.html'.to_sym
      end

      get '/edit_contacts' do
        erb 'edit_contacts.html'.to_sym
      end

      get "/contacts/:id" do
        contact_id = params[:id]

        @contact = Flapjack::Data::Contact.find_by_id(contact_id)
        halt(404, "Could not find contact '#{contact_id}'") if @contact.nil?

        @contact_media = @contact.media.all

        if @contact_media.any? {|m| m.transport == 'pagerduty'}
          @pagerduty_credentials = @contact.pagerduty_credentials
        end

        erb 'contact.html'.to_sym
      end

    private

      def check_state(check, time)
        latest_notif = check.latest_notifications.last

        lc = check.states.last
        last_change   = lc.nil? ? 'never' :
          (ChronicDuration.output(time.to_i - lc.timestamp.to_i,
                                  :format => :short, :keep_zero => true,
                                  :units => 2) || '0s')

        lu = lc.nil? ? nil : lc.entries.last
        last_update   = lu.nil? ? 'never' :
          (ChronicDuration.output(time.to_i - lu.timestamp.to_i,
                                  :format => :short, :keep_zero => true,
                                  :units => 2) || '0s')

        summary = nil
        cond    = nil

        if latest_notif.nil?
          last_notified = 'never'
        else
          cond = latest_notif.condition

          summary = latest_notif.summary
          summary = summary[0..76] + '...' unless summary.nil? || (summary.length < 81)

          ln = latest_notif.timestamp

          last_notified = (ChronicDuration.output(time.to_i - ln.to_i,
                           :format => :short, :keep_zero => true, :units => 2) || '0s')
        end

        [(cond     || '-'),
         (summary  || '-'),
         last_change,
         last_update,
         check.in_unscheduled_maintenance?,
         check.in_scheduled_maintenance?,
         last_notified
        ]
      end

      def self_stats(time)
        @fqdn    = `/bin/hostname -f`.chomp
        @pid     = Process.pid
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
        @failing_checks ||= Flapjack::Data::Check.all.each_with_object([]) do |check, memo|
          s = check.states.last
          next if s.nil? || Flapjack::Data::Condition.healthy?(s.condition)
          memo << check
        end
      end

      def check_stats
        @count_enabled_checks = Flapjack::Data::Check.intersect(:enabled => true).count
        @count_failing_checks = failing_checks.size
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
          "<script type='text/javascript' src='#{link_to("js/#{filename}.js")}'></script>"
        }.join("\n    ")
      end

      def include_required_css
        return "" if @required_css.nil?
        @required_css.map { |filename|
          %(<link rel="stylesheet" href="#{link_to("css/#{filename}.css")}" media="screen">)
        }.join("\n    ")
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
