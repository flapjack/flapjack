#!/usr/bin/env ruby

require 'chronic'
require 'chronic_duration'
require 'sinatra/base'
require 'tilt/erb'
require 'uri'

require 'flapjack/gateways/api_web/middleware/request_timestamp'

require 'flapjack-diner'

require 'flapjack/utility'

module Flapjack

  module Gateways

    class ApiWeb < Sinatra::Base

      set :root, File.dirname(__FILE__)

      use Flapjack::Gateways::ApiWeb::Middleware::RequestTimestamp
      use Rack::MethodOverride

      set :raise_errors, false
      set :protection, except: :path_traversal

      set :views, settings.root + '/api_web/views'
      set :public_folder, settings.root + '/api_web/public'

      set :erb, :layout => 'layout.html'.to_sym

      class << self
        def start
          Flapjack.logger.info "starting api_web - class"

          set :show_exceptions, false
          @show_exceptions = Sinatra::ShowExceptions.new(self)

          if access_log = (@config && @config['access_log'])
            unless File.directory?(File.dirname(access_log))
              raise "Parent directory for log file #{access_log} doesn't exist"
            end

            use Rack::CommonLogger, ::Logger.new(@config['access_log'])
          end

          # FIXME don't need an instance variable for @api_url any more
          @api_url = @config['api_url']
          if @api_url
            if URI.regexp(['http', 'https']).match(@api_url).nil?
              Flapjack.logger.error "api_url is not a valid http or https URI (#{@api_url}), discarding"
              @api_url = nil
              # FIXME raise error
            end
            unless @api_url.match(/^.*\/$/)
              Flapjack.logger.info "api_url must end with a trailing '/', setting to '#{@api_url}/'"
              @api_url = "#{@api_url}/"
            end
          else
            # FIXME raise error
          end

          Flapjack::Diner.base_uri(@api_url) unless @api_url.nil?
          Flapjack::Diner.logger = ::Logger.new('log/flapjack_diner.log')

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

        def charset_for_content_type(ct)
          charset = Encoding.default_external
          charset.nil? ? ct : "#{ct}; charset=#{charset.name}"
        end
      end

      ['config'].each do |class_inst_var|
        define_method(class_inst_var.to_sym) do
          self.class.instance_variable_get("@#{class_inst_var}")
        end
      end

      before do
        content_type charset_for_content_type('text/html')

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
        @metrics = Flapjack::Diner.metrics

        erb 'index.html'.to_sym
      end

      get '/self_stats' do
        @current_time = Time.now

        @metrics   = Flapjack::Diner.metrics
        statistics = Flapjack::Diner.statistics

        unless statistics.nil?
          @executive_instances = statistics.each_with_object({}) do |stats, memo|
            if 'global'.eql?(stats[:instance_name])
              @global_stats = stats
              next
            end
            boot_time =  Time.parse(stats[:created_at])
            uptime = @current_time - boot_time
            uptime_string = ChronicDuration.output(uptime, :format => :short,
                              :keep_zero => true, :units => 2) || '0s'

            event_counters = {}
            event_rates    = {}

            [:all_events, :ok_events, :failure_events, :action_events,
             :invalid_events].each do |evt|

              count               = stats[evt]
              event_counters[evt] = count
              event_rates[evt]    = (uptime > 0) ? (count.to_f / uptime).round : nil
            end

            memo[stats[:instance_name]] = {
              :uptime         => uptime,
              :uptime_string  => uptime_string,
              :event_counters => event_counters,
              :event_rates    => event_rates
            }
          end
        end

        erb 'self_stats.html'.to_sym
      end

      get '/tags' do
        opts = {}
        @name = params[:name]
        opts.update(:name => @name) unless @name.nil? || @name.empty?

        @tags = Flapjack::Diner.tags(:filter => opts,
          :page => (params[:page] || 1))

        erb 'tags.html'.to_sym
      end

      get '/tags/:name' do
        tag_name = params[:name]

        @tag = Flapjack::Diner.tags(tag_name)
        err(404, "Could not find tag '#{tag_name}'") if @tag.nil?

        check_ids = Flapjack::Diner.tag_link_checks(tag_name)
        err(404, "Could not find checks for tag '#{tag_name}'") if check_ids.nil?

        erb 'tag.html'.to_sym
      end

      get '/checks' do
        time = Time.now

        opts = {}

        @name = params[:name]
        opts.update(:name => @name) unless @name.nil? || @name.empty?

        @enabled = boolean_from_str(params[:enabled])
        opts.update(:enabled => @enabled) unless @enabled.nil?

        @failing = boolean_from_str(params[:failing])
        opts.update(:failing => @failing) unless @failing.nil?

        @checks = Flapjack::Diner.checks(:filter => opts,
                    :page => (params[:page] || 1),
                    :include => 'current_state,latest_notifications,' \
                      'current_scheduled_maintenances,' \
                      'current_unscheduled_maintenance')

        @states = {}

        unless @checks.nil? || @checks.empty?
          @pagination = pagination_from_context(Flapjack::Diner.context)
          unless @pagination.nil?
            @links = create_pagination_links(@pagination[:page],
              @pagination[:total_pages])
          end

          included = Flapjack::Diner.context[:included]

          unless included.nil? || included.empty?
            @states = @checks.each_with_object({}) do |check, memo|
              memo[check.id] = check_state(check, included)
            end
          end
        end

        erb 'checks.html'.to_sym
      end

      get '/checks/:id' do
        check_id  = params[:id]

        @current_time = Time.now

        @check = Flapjack::Diner.checks(check_id,
                   :include => 'contacts,contacts.media,current_state,' \
                               'latest_notifications,' \
                               'current_scheduled_maintenances,' \
                               'current_unscheduled_maintenance')

        halt(404, "Could not find check '#{check_id}'") if @check.nil?

        included = Flapjack::Diner.context[:included]

        unless included.nil? || included.empty?
          @state = check_extra_state(check, included)
        end

        # will only get first page of 20 records
        @state_changes = Flapjack::Diner.check_links_states(check_id)

        @acknowledgement_id = 'ok'.eql?(@check[:condition]) ? nil : @check.ack_hash

        @contacts = included_records(check[:links], :contacts,
          included, 'contact')

        @contact_media = included_records(check[:links], :'contacts.media',
          included, 'medium')

        erb 'check.html'.to_sym
      end

    #   post "/unscheduled_maintenances/checks/:id" do
    #     check_id           = params[:id]
    #     summary            = params[:summary]
    #     acknowledgement_id = params[:acknowledgement_id]

    #     dur = ChronicDuration.parse(params[:duration] || '')
    #     duration = (dur.nil? || (dur <= 0)) ? (4 * 60 * 60) : dur

    #     check = Flapjack::Data::Check.find_by_id(check_id)
    #     halt(404, "Could not find check '#{check_id}'") if check.nil?

    #     ack = Flapjack::Data::Event.create_acknowledgements(
    #       config['processor_queue'] || 'events',
    #       [check],
    #       :summary => (summary || ''),
    #       :acknowledgement_id => acknowledgement_id,
    #       :duration => duration,
    #     )

    #     redirect back
    #   end

    #   patch '/unscheduled_maintenances/checks/:id' do
    #     check_id  = params[:id]

    #     check = Flapjack::Data::Check.find_by_id(check_id)
    #     halt(404, "Could not find check '#{check_id}'") if check.nil?

    #     check.clear_unscheduled_maintenance(Time.now.to_i)

    #     redirect back
    #   end

    #   # create scheduled maintenance
    #   post '/scheduled_maintenances/checks/:id' do
    #     check_id  = params[:id]

    #     start_time = Chronic.parse(params[:start_time]).to_i
    #     raise ArgumentError, "start time parsed to zero" unless start_time > 0
    #     duration   = ChronicDuration.parse(params[:duration])
    #     summary    = params[:summary]

    #     check = Flapjack::Data::Check.find_by_id(check_id)
    #     halt(404, "Could not find check '#{check_id}'") if check.nil?

    #     sched_maint = Flapjack::Data::ScheduledMaintenance.new(:start_time => start_time,
    #       :end_time => start_time + duration, :summary => summary)
    #     sched_maint.save
    #     check.scheduled_maintenances << sched_maint

    #     redirect back
    #   end

    #   # delete a scheduled maintenance
    #   delete '/scheduled_maintenances/checks/:id' do
    #     check_id  = params[:id]

    #     # TODO better error checking on this param?
    #     start_time = Time.parse(params[:start_time])

    #     check = Flapjack::Data::Check.find_by_id(check_id)
    #     halt(404, "Could not find check '#{check_id}'") if check.nil?

    #     # TODO maybe intersect_range should auto-coerce for timestamp fields?
    #     # (actually, this should just pass sched maint ID in now that it can)
    #     sched_maints = check.scheduled_maintenances_by_start.
    #       intersect_range(start_time.to_i, start_time.to_i, :by_score => true).all
    #     halt(404, "No scheduled maintenance periods found") if sched_maints.empty?

    #     sched_maints.each do |sched_maint|
    #       check.end_scheduled_maintenance(sched_maint, Time.now)
    #     end

    #     redirect back
    #   end

      get '/contacts' do
        opts = {}
        @name = params[:name]
        opts.update(:name => @name) unless @name.nil?

        @contacts = Flapjack::Diner.contacts(:page => params[:page],
          :filter => opts, :sort => '+name')

        unless @contacts.nil?
          @pagination = pagination_from_context(Flapjack::Diner.context)
          unless @pagination.nil?
            @links = create_pagination_links(@pagination[:page],
              @pagination[:total_pages])
          end
        end

        erb 'contacts.html'.to_sym
      end

      get "/contacts/:id" do
        contact_id = params[:id]

        @contact = Flapjack::Diner.contacts(contact_id, :include => 'media')
        halt(404, "Could not find contact '#{contact_id}'") if @contact.nil?

        context = Flapjack::Diner.context
        @media = context[:included] unless context.nil?

        # check_refs = Flapjack::Diner.contacts_link_checks(contact_id)
        # unless check_refs.nil?
          # check_ids  =
        # end

        @checks = []

        erb 'contact.html'.to_sym
      end

      error do
        e = env['sinatra.error']
        # trace = e.backtrace.join("\n")
        # puts trace

        # Rack::CommonLogger doesn't log requests which result in exceptions.
        # If you want something done properly, do it yourself...
        access_log = self.class.instance_variable_get('@middleware').detect {|mw|
          mw.first.is_a?(::Rack::CommonLogger)
        }
        unless access_log.nil?
          access_log.first.send(:log, status_code,
            ::Rack::Utils::HeaderHash.new(headers), msg,
            env['request_timestamp'])
        end
        self.class.instance_variable_get('@show_exceptions').pretty(env, e)
      end

    private

      def check_state(check, included)
        current_state_id = check[:links][:current_state][:linkage][:id]

        current_state = current_state_id.nil? ? nil : included.detect do |incl|
           'state'.eql?(incl[:type]) && current_state_id.eql?(incl[:id])
        end

        current_state = included_records(check[:links], :current_state,
          included, 'state')

        latest_notifications = included_records(check[:links], :latest_notifications,
          included, 'state')

        in_scheduled_maintenance = !check[:links][:current_scheduled_maintenances][:linkage].nil? &&
          !check[:links][:latest_notifications][:linkage].empty?

        in_unscheduled_maintenance = !check[:links][:current_unscheduled_maintenance][:linkage].nil?

        # get latest (by time) of the latest notifications
        notif_times = latest_notifications.each_with_object({}) do |ln, memo|
          begin
            memo[ln[:id]] = DateTime.parse(ln[:created_at]).to_i
          rescue ArgumentError
            Flapjack.logger.warn("error parsing notification :created_at ( #{ln.inspect} )")
          end
        end

        latest_notification_id_time = notif_times.sort_by {|id, ti| ti}

        last_notification = latest_notification_id_time.nil? ? nil :
          latest_notifications.detect {|ln| latest_notification_id_time[0].eql?(ln[:id]) }

        {
          :condition     => current_state.nil? ? '-' : current_state[:condition],
          :summary       => current_state.nil? ? '-' : current_state[:summary],
          :latest_notifications => (latest_notifications || []),
          :last_changed  => render_state_duration(time, current_state, :created_at),
          :last_updated  => render_state_duration(time, current_state, :updated_at),
          :last_notified => render_state_duration(time, last_notification, :created_at),
          :in_scheduled_maintenance => in_scheduled_maintenance,
          :in_unscheduled_maintenance => in_unscheduled_maintenance
        }
      end

      def check_extra_state(check, included)
        state = check_state(check, included)

        current_scheduled_maintenances = included_records(check[:links],
          :current_scheduled_maintenances, included, 'scheduled_maintenance')

        current_unscheduled_maintenance = included_records(check[:links],
          :current_unscheduled_maintenance, included, 'unscheduled_maintenance')

        #     @last_notifications = @check.latest_notifications.all.each_with_object({}) do |entry, memo|
        #       t = Time.at(entry.timestamp)
        #       memo[(entry.action || entry.condition).to_sym] = {
        #         :time => t.to_s,
        #         :relative => relative_time_ago(@current_time, t) + " ago",
        #         :summary => entry.summary
        #       }
        #     end

        #     # # don't think this is needed any more
        #     # @last_notifications[:acknowledgement] =
        #     #   @check.states.intersect(:action => 'acknowledgement',
        #     #                           :notified => true).last

        state.merge(
          :details       => current_state.nil? ? '-' : current_state[:details],
          :perfdata      => current_state.nil? ? '-' : current_state[:perfdata],
          :current_scheduled_maintenances => (current_scheduled_maintenances || []),
          :current_unscheduled_maintenance => current_unscheduled_maintenance
        )
      end

      def included_records(links, field, included, type)
        return unless links.has_key?(field) && links[field].has_key?(:linkage) &&
          !links[field][:linkage].nil?

        if links[field][:linkage].is_a?(Array)
          ids = links[field][:linkage].collect {|lr| lr[:id]}
          return [] if ids.empty?

          included.select do |incl|
            type.eql?(incl[:type]) && ids.include?(incl[:id])
          end
        else
          id = links[field][:linkage][:id]
          return if id.nil?

          included.detect do |incl|
            type.eql?(incl[:type]) && id.eql?(incl[:id])
          end
        end
      end

      def pagination_from_context(context)
        ((context || {})[:meta] || {})[:pagination]
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

      def boolean_from_str(str)
        case str
        when '0', 'f', 'false', 'n', 'no'
          false
        when '1', 't', 'true', 'y', 'yes'
          true
        end
      end

      def create_pagination_links(page, total_pages)
        pages = {}
        pages[:first] = 1
        pages[:prev]  = page - 1 if (page > 1)
        pages[:next]  = page + 1 if page < total_pages
        pages[:last]  = total_pages

        url_without_params = request.url.split('?').first

        links = {}
        pages.each do |key, value|
          page_params = {'page' => value }
          new_params = request.params.merge(page_params)
          links[key] = "#{url_without_params}?#{new_params.to_query}"
        end
        links
      end

      def render_state_duration(base_time, state, field)
        if state.nil? || state[field].nil?
          'never'
        else
          begin
            parsed = DateTime.parse(state[field])
            ChronicDuration.output(base_time.to_i - parsed.to_i,
                                   :format => :short, :keep_zero => true,
                                   :units => 2) || '0s'
          rescue ArgumentError
            Flapjack.logger.warn("error parsing time field #{field} ( #{state.inspect} )")
            "error parsing time field #{field}"
          end
        end
      end

    end
  end
end
