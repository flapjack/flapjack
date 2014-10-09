#!/usr/bin/env ruby

require 'dante'
require 'redis'
require 'hiredis'

require 'flapjack/configuration'
require 'flapjack/data/event'
require 'flapjack/patches'

# TODO options should be overridden by similar config file options

module Flapjack
  module CLI
    class Receiver

      def initialize(global_options, options)
        @global_options = global_options
        @options = options

        @config = Flapjack::Configuration.new
        @config.load(global_options[:config])
        @config_env = @config.all

        if @config_env.nil? || @config_env.empty?
          unless 'mirror'.eql?(@options[:type])
            exit_now! "No config data for environment '#{FLAPJACK_ENV}' found in '#{global_options[:config]}'"
          end

          @config_env = {}
          @config_runner = {}
        else
          @config_runner = @config_env["#{@options[:type]}-receiver"] || {}
        end

        @redis_options = @config.for_redis
      end

      def pidfile
        @pidfile ||= case
        when !@options[:pidfile].nil?
          @options[:pidfile]
        when !@config_env['pid_dir'].nil?
          File.join(@config_env['pid_dir'], "#{@options[:type]}-receiver.pid")
        else
          "/var/run/flapjack/#{@options[:type]}-receiver.pid"
        end
      end

      def logfile
        @logfile ||= case
        when !@options[:logfile].nil?
          @options[:logfile]
        when !@config_env['log_dir'].nil?
          File.join(@config_env['log_dir'], "#{@options[:type]}-receiver.log")
        else
          "/var/run/flapjack/#{@options[:type]}-receiver.log"
        end
      end

      def start
        if runner(@options[:type]).daemon_running?
          puts "#{@options[:type]}-receiver is already running."
        else
          print "#{@options[:type]}-receiver starting..."
          print "\n" unless @options[:daemonize]
          runner(@options[:type]).execute(:daemonize => @options[:daemonize]) do
            begin
              main(:fifo => @options[:fifo], :type => @options[:type])
            rescue Exception => e
              p e.message
              puts e.backtrace.join("\n")
            end
          end
          puts " done."
        end
      end

      def stop
        pid = get_pid
        if runner(@options[:type]).daemon_running?
          print "#{@options[:type]}-receiver stopping..."
          runner(@options[:type]).execute(:kill => true)
          puts " done."
        else
          puts "#{@options[:type]}-receiver is not running."
        end
        exit_now! unless wait_pid_gone(pid)
      end

      def restart
        print "#{@options[:type]}-receiver restarting..."
        runner(@options[:type]).execute(:daemonize => true, :restart => true) do
          begin
            main(:fifo => @options[:fifo], :type => @options[:type])
          rescue Exception => e
            p e.message
            puts e.backtrace.join("\n")
          end
        end
        puts " done."
      end

      def status
        if runner(@options[:type]).daemon_running?
          pid = get_pid
          uptime = Time.now - File.stat(pidfile).ctime
          puts "#{@options[:type]}-receiver is running: pid #{pid}, uptime #{uptime}"
        else
          exit_now! "#{@options[:type]}-receiver is not running"
        end
      end

      def json
        json_feeder(:from => @options[:from])
      end

      def mirror
        if (@options[:dest].nil? || @options[:dest].strip.empty?) &&
          @redis_options.nil?

          exit_now! "No destination redis URL passed, and none configured"
        end

        mirror_receive(:source => @options[:source],
          :dest => @options[:dest] || @redis_options,
          :include => @options[:include], :all => @options[:all],
          :follow => @options[:follow], :last => @options[:last],
          :time => @options[:time])
      end

      private

      def redis
        @redis ||= Redis.new(@redis_options.merge(:driver => :hiredis))
      end

      def runner(type)
        return @runner if @runner

        @runner = Dante::Runner.new("#{@options[:type]}-receiver", :pid_path => pidfile,
          :log_path => logfile)
        @runner
      end

      def process_input(opts)
        config_rec = case opts[:type]
        when /nagios/
          @config_env['nagios-receiver'] || {}
        when /nsca/
          @config_env['nsca-receiver'] || {}
        else
          raise "Unknown receiver type"
        end

        opt_fifo = (opts[:fifo] || config_rec['fifo'] || '/var/cache/nagios3/event_stream.fifo')
        unless File.exist?(opt_fifo)
          raise "No fifo (named pipe) file found at #{opt_fifo}"
        end
        unless File.pipe?(opt_fifo)
          raise "The file at #{opt_fifo} is not a named pipe, try using mkfifo to make one"
        end
        unless File.readable?(opt_fifo)
          raise "The fifo (named pipe) at #{opt_fifo} is unreadable"
        end

        fifo  = File.new(opt_fifo)
        begin
          while line = fifo.gets
            skip unless line
            split_line = line.split("\t")

            object_type, timestamp, entity, check, state, check_time,
              check_latency, check_output, check_perfdata, check_long_output =
               [nil] * 10

            case opts[:type]
            when /nagios/
              object_type, timestamp, entity, check, state, check_time,
                check_latency, check_output, check_perfdata, check_long_output = split_line

              case
              when split_line.length < 9
                puts "ERROR - rejecting this line as it doesn't split into at least 9 tab separated strings: [#{line}]"
                next
              when timestamp !~ /^\d+$/
                puts "ERROR - rejecting this line as second string doesn't look like a timestamp: [#{line}]"
                next
              when (object_type != '[HOSTPERFDATA]') && (object_type != '[SERVICEPERFDATA]')
                puts "ERROR - rejecting this line as first string is neither '[HOSTPERFDATA]' nor '[SERVICEPERFDATA]': [#{line}]"
                next
              end

            when /nsca/

              timestamp, passivecheck = split_line
              split_passive = passivecheck.split(";")
              timestamp = timestamp.delete('[]')

              check_long_output = ''
              object_type, entity, check, state, check_output = split_passive

              case
              when (split_line.length < 2 || split_passive.length < 5)
                puts "ERROR - rejecting this line; illegal format: [#{line}]"
                next
              when (timestamp !~ /^\d+$/)
                puts "ERROR - rejecting this line; timestamp look like a timestamp: [#{line}]"
                next
              when (object_type != 'PROCESS_SERVICE_CHECK_RESULT')
                puts "ERROR - rejecting this line; identifier 'PROCESS_SERVICE_CHECK_RESULT' is missing: [#{line}]"
                next
              end

            end

            puts "#{object_type}, #{timestamp}, #{entity}, #{check}, #{state}, #{check_output}, #{check_long_output}"

            state = 'ok'       if state.downcase == 'up'
            state = 'critical' if state.downcase == 'down'
            details = check_long_output ? check_long_output.gsub(/\\n/, "\n") : nil
            event = {
              'entity'    => entity,
              'check'     => check,
              'type'      => 'service',
              'state'     => state,
              'summary'   => check_output,
              'details'   => details,
              'perfdata'  => check_perfdata,
              'time'      => timestamp,
            }
            Flapjack::Data::Event.add(event, :redis => redis)
          end
        rescue Redis::CannotConnectError
          puts "Error, unable to to connect to the redis server (#{$!})"
        end
      end

      def main(opts)
        fifo = opts[:fifo]
        while true
          process_input(:fifo => fifo, :type => opts[:type])
          puts "Whoops with the fifo, restarting main loop in 10 seconds"
          sleep 10
        end
      end

      def process_exists(pid)
        return unless pid
        begin
          Process.kill(0, pid)
          return true
        rescue Errno::ESRCH
          return false
        end
      end

      # wait until the specified pid no longer exists, or until a timeout is reached
      def wait_pid_gone(pid, timeout = 30)
        print "waiting for a max of #{timeout} seconds for process #{pid} to exit" if process_exists(pid)
        started_at = Time.now.to_i
        while process_exists(pid)
          break unless (Time.now.to_i - started_at < timeout)
          print '.'
          sleep 1
        end
        puts ''
        !process_exists(pid)
      end

      def get_pid
        IO.read(pidfile).chomp.to_i
      rescue StandardError
        pid = nil
      end

      class EventFeedHandler < Oj::ScHandler

        def initialize(&block)
          @hash_depth = 0
          @callback = block if block_given?
        end

        def hash_start
          @hash_depth += 1
          Hash.new
        end

        def hash_end
          @hash_depth -= 1
        end

        def array_start
          Array.new
        end

        def array_end
        end

        def add_value(value)
          @callback.call(value) if @callback
          nil
        end

        def hash_set(hash, key, value)
          hash[key] = value
        end

        def array_append(array, value)
          array << value
        end

      end

      def json_feeder(opts = {})
        input = if opts[:from]
          File.open(opts[:from]) # Explodes if file does not exist.
        elsif $stdin.tty?
          exit_now! "No file provided, and STDIN is from terminal! Exiting..."
        else
          $stdin
        end

        # Sit and churn through the input stream until a valid JSON blob has been assembled.
        # This handles both the case of a process sending a single JSON and then exiting
        # (eg. cat foo.json | bin/flapjack receiver json) *and* a longer-running process spitting
        # out events (eg. /usr/bin/slow-event-feed | bin/flapjack receiver json)

        parser = EventFeedHandler.new do |parsed|
          # Handle "parsed" (a hash)
          errors = Flapjack::Data::Event.validation_errors_for_hash(parsed)
          if errors.empty?
            Flapjack::Data::Event.add(parsed, :redis => redis)
            puts "Enqueued event data, #{parsed.inspect}"
          else
            puts "Invalid event data received, #{errors.join(', ')} #{parsed.inspect}"
          end
        end

        Oj.sc_parse(parser, input)

        puts "Done."
      end

      def mirror_receive(opts)
        unless opts[:follow] || opts[:all]
          exit_now! "one or both of --follow or --all is required"
        end

        include_re = nil
        unless opts[:include].nil? || opts[:include].strip.empty?
          begin
            include_re = Regexp.new(opts[:include].strip)
          rescue RegexpError
            exit_now! "could not parse include Regexp: #{opts[:include].strip}"
          end
        end

        source_addr = opts[:source]
        source_redis = Redis.new(:url => source_addr, :driver => :hiredis)

        dest_addr  = opts[:dest]
        dest_redis = case dest_addr
        when Hash
          Redis.new(dest_redis.merge(:driver => :hiredis))
        when String
          Redis.new(:url => dest_addr, :driver => :hiredis)
        else
          exit_now! "could not understand destination Redis config"
        end

        refresh_archive_index(source_addr, :source => source_redis, :dest => dest_redis)
        archives = mirror_get_archive_keys_stats(source_addr, :source => source_redis,
          :dest => dest_redis)
        raise "found no archives!" if archives.empty?

        puts "found archives: #{archives.inspect}"

        # each archive bucket is a redis list that is written
        # with brpoplpush, that is newest items are added to the left (head)
        # of the list, so oldest events are to be found at the tail of the list.
        #
        # the index of these archives, in the 'archives' array, also stores the
        # redis key names for each bucket in oldest to newest
        events_sent = 0
        case
        when opts[:all]
          archive_idx = 0
          cursor      = -1
        when opts[:last], opts[:time]
          raise "Sorry, unimplemented"
        else
          # wait for the next event to be archived, so point the cursor at a non-existant
          # slot in the list, the one before the 0'th
          archive_idx = archives.size - 1
          cursor      = -1 - archives[-1][:size]
        end

        archive_key = archives[archive_idx][:name]
        puts archive_key

        loop do
          event_json = source_redis.lindex(archive_key, cursor)
          if event_json
            event = Flapjack::Data::Event.parse_and_validate(event_json)
            if !event.nil? && (include_re.nil? ||
              (include_re === "#{event['entity']}:#{event['check']}"))

              Flapjack::Data::Event.add(event, :redis => dest_redis)
              events_sent += 1
              print "#{events_sent} " if events_sent % 1000 == 0
            end
            cursor -= 1
            next
          end

          archives = mirror_get_archive_keys_stats(source_addr,
            :source => source_redis, :dest => dest_redis)

          if archives.any? {|a| a[:size] == 0}
            # data may be out of date -- refresh, then reject any immediately
            # expired keys directly; don't keep chasing updated data
            refresh_archive_index(source_addr, :source => source_redis, :dest => dest_redis)
            archives = mirror_get_archive_keys_stats(source_addr,
              :source => source_redis, :dest => dest_redis).select {|a| a[:size] > 0}
          end

          if archives.empty?
            sleep 1
            next
          end

          archive_idx = archives.index {|a| a[:name] == archive_key }
          archive_idx = archive_idx.nil? ? 0 : (archive_idx + 1)
          if archives[archive_idx]
            archive_key = archives[archive_idx][:name]
            puts archive_key
            cursor = -1
          else
            break unless opts[:follow]
            sleep 1
          end
        end
      end

      def mirror_get_archive_keys_stats(name, opts = {})
        source_redis = opts[:source]
        dest_redis   = opts[:dest]
        dest_redis.smembers("known_events_archive_keys:#{name}").sort.collect do |eak|
          {:name => eak, :size => source_redis.llen(eak)}
        end
      end

      def refresh_archive_index(name, opts = {})
        source_redis = opts[:source]
        dest_redis   = opts[:dest]
        # refresh the key name cache, avoid repeated calls to redis KEYS
        # this cache will be updated any time a new archive bucket is created
        archive_keys = source_redis.keys("events_archive:*").group_by do |ak|
          (source_redis.llen(ak) > 0) ? 't' : 'f'
        end

        {'f' => :srem, 't' => :sadd}.each_pair do |k, cmd|
          next unless archive_keys.has_key?(k) && !archive_keys[k].empty?
          dest_redis.send(cmd, "known_events_archive_keys:#{name}", archive_keys[k])
        end
      end

    end
  end
end

desc 'Receive events from external systems and sends them to Flapjack'
arg_name 'receiver'
command :receiver do |receiver|

  receiver.desc 'Nagios receiver'
  #receiver.arg_name 'Turn Nagios check results into Flapjack events'
  receiver.command :nagios do |nagios|

    # # Not sure what to do with this, was 'extended help'

    #     puts '
    # Required Nagios Configuration Changes
    # -------------------------------------

    # flapjack-nagios-receiver reads events from a named pipe written to by Nagios. The named pipe needs creating, and Nagios needs to be told to write performance data output to it.

    # To create the named pipe:

    #   mkfifo -m 0666 /var/cache/nagios3/event_stream.fifo

    # nagios.cfg changes:

    #   # modified lines:
    #   enable_notifications=0
    #   host_perfdata_file=/var/cache/nagios3/event_stream.fifo
    #   service_perfdata_file=/var/cache/nagios3/event_stream.fifo
    #   host_perfdata_file_template=[HOSTPERFDATA]\t$TIMET$\t$HOSTNAME$\tHOST\t$HOSTSTATE$\t$HOSTEXECUTIONTIME$\t$HOSTLATENCY$\t$HOSTOUTPUT$\t$HOSTPERFDATA$
    #   service_perfdata_file_template=[SERVICEPERFDATA]\t$TIMET$\t$HOSTNAME$\t$SERVICEDESC$\t$SERVICESTATE$\t$SERVICEEXECUTIONTIME$\t$SERVICELATENCY$\t$SERVICEOUTPUT$\t$SERVICEPERFDATA$
    #   host_perfdata_file_mode=p
    #   service_perfdata_file_mode=p

    # Details on the wiki: http://flapjack.io/docs/1.0/usage/USING#configuring-nagios
    # '

    nagios.command :start do |start|

      start.switch [:d, 'daemonize'], :desc => 'Daemonize',
        :default_value => true

      start.flag   [:p, 'pidfile'],   :desc => 'PATH of the pidfile to write to'

      start.flag   [:l, 'logfile'],   :desc => 'PATH of the logfile to write to'

      start.flag   [:f, 'fifo'],      :desc => 'PATH of the nagios perfdata named pipe'

      start.action do |global_options,options,args|
        options.merge!(:type => 'nagios')
        receiver = Flapjack::CLI::Receiver.new(global_options, options)
        receiver.start
      end
    end

    nagios.command :stop do |stop|

      stop.flag   [:p, 'pidfile'],   :desc => 'PATH of the pidfile to write to'

      stop.flag   [:l, 'logfile'],   :desc => 'PATH of the logfile to write to'

      stop.action do |global_options,options,args|
        options.merge!(:type => 'nagios')
        receiver = Flapjack::CLI::Receiver.new(global_options, options)
        receiver.stop
      end
    end

    nagios.command :restart do |restart|

      restart.flag   [:p, 'pidfile'],   :desc => 'PATH of the pidfile to write to'

      restart.flag   [:l, 'logfile'],   :desc => 'PATH of the logfile to write to'

      restart.flag   [:f, 'fifo'],      :desc => 'PATH of the nagios perfdata named pipe'

      restart.action do |global_options,options,args|
        options.merge!(:type => 'nagios')
        receiver = Flapjack::CLI::Receiver.new(global_options, options)
        receiver.restart
      end
    end

    nagios.command :status do |status|

      status.flag   [:p, 'pidfile'],   :desc => 'PATH of the pidfile to write to'

      status.flag   [:l, 'logfile'],   :desc => 'PATH of the logfile to write to'

      status.action do |global_options,options,args|
        options.merge!(:type => 'nagios')
        receiver = Flapjack::CLI::Receiver.new(global_options, options)
        receiver.status
      end
    end

  end

  receiver.desc 'NSCA receiver'
  #receiver.arg_name 'Turn Nagios passive check results into Flapjack events'
  receiver.command :nsca do |nsca|

    nsca.command :start do |start|

      # # Not sure what to do with this, extra help output:

      # Required Nagios Configuration Changes
      # -------------------------------------

      # flapjack-nsca-receiver reads events from the nagios "command file" read from by Nagios, written to by the Nsca-daemon.

      # The named pipe is automatically created by _nagios_ if it is enabled
      # in the configfile:

      #   # modified lines:
      #   command_file=/var/lib/nagios3/rw/nagios.cmd

      # The Nsca daemon is optionally writing to a tempfile if the named pipe does
      # not exist.

      # Details on the wiki: http://flapjack.io/docs/1.0/usage/USING#XXX
      # '

      start.switch [:d, 'daemonize'], :desc => 'Daemonize',
        :default_value => true

      start.flag   [:p, 'pidfile'],   :desc => 'PATH of the pidfile to write to'

      start.flag   [:l, 'logfile'],   :desc => 'PATH of the logfile to write to'

      start.flag   [:f, 'fifo'],      :desc => 'PATH of the nagios perfdata named pipe'

      start.action do |global_options,options,args|
        options.merge!(:type => 'nsca')
        receiver = Flapjack::CLI::Receiver.new(global_options, options)
        receiver.start
      end
    end

    nsca.command :stop do |stop|

      stop.flag   [:p, 'pidfile'],   :desc => 'PATH of the pidfile to write to'

      stop.flag   [:l, 'logfile'],   :desc => 'PATH of the logfile to write to'

      stop.action do |global_options,options,args|
        options.merge!(:type => 'nsca')
        receiver = Flapjack::CLI::Receiver.new(global_options, options)
        receiver.stop
      end
    end

    nsca.command :restart do |restart|

      restart.flag   [:p, 'pidfile'],   :desc => 'PATH of the pidfile to write to'

      restart.flag   [:l, 'logfile'],   :desc => 'PATH of the logfile to write to'

      restart.flag   [:f, 'fifo'],      :desc => 'PATH of the nagios perfdata named pipe'

      restart.action do |global_options,options,args|
        options.merge!(:type => 'nsca')
        receiver = Flapjack::CLI::Receiver.new(global_options, options)
        receiver.restart
      end
    end

    nsca.command :status do |status|

      status.flag   [:p, 'pidfile'],   :desc => 'PATH of the pidfile to write to'

      status.flag   [:l, 'logfile'],   :desc => 'PATH of the logfile to write to'

      status.action do |global_options,options,args|
        options.merge!(:type => 'nsca')
        receiver = Flapjack::CLI::Receiver.new(global_options, options)
        receiver.status
      end
    end

  end

  receiver.desc 'JSON receiver'
  receiver.command :json do |json|

    json.flag [:f, 'from'],     :desc => 'PATH of the file to process [STDIN]'

    json.action do |global_options,options,args|
      receiver = Flapjack::CLI::Receiver.new(global_options, options)
      receiver.json
    end
  end

  receiver.desc 'Mirror receiver'
  receiver.command :mirror do |mirror|

    mirror.flag     [:s, 'source'], :desc => 'URL of source redis database, e.g. redis://localhost:6379/0',
      :required => true

    mirror.flag     [:d, 'dest'],   :desc => 'URL of destination redis database, e.g. redis://localhost:6379/1'

    mirror.flag     [:i, 'include'], :desc => 'Regexp which must match event id for it to be mirrored'

    # one or both of follow, all is required
    mirror.switch   [:f, 'follow'], :desc => 'keep reading events as they are archived on the source',
      :default_value => nil

    mirror.switch   [:a, 'all'],    :desc => 'replay all archived events from the source',
      :default_value => nil

    # options.count in code
    mirror.flag     [:l, 'last'],   :desc => 'replay the last COUNT events from the source',
      :default_value => nil

    # options.since in code
    mirror.flag     [:t, 'time'],   :desc => 'replay all events archived on the source since TIME',
      :default_value => nil

    mirror.action do |global_options,options,args|
      options.merge!(:type => 'mirror')
      receiver = Flapjack::CLI::Receiver.new(global_options, options)
      receiver.mirror
    end
  end


  receiver.desc 'One-off event submitter'
  receiver.command :oneoff do |oneoff|
    oneoff.passthrough = true
    oneoff.action do |global_options, options, args|
      libexec = Pathname.new(__FILE__).parent.parent.parent.parent.join('libexec').expand_path
      oneoff  = libexec.join('oneoff')
      if oneoff.exist?
        Kernel.exec(oneoff.to_s, *ARGV)
      end
    end
  end

  receiver.desc 'HTTP checker for availability checking of services'
  receiver.command :httpchecker do |httpchecker|
    httpchecker.passthrough = true
    httpchecker.action do |global_options, options, args|
      libexec = Pathname.new(__FILE__).parent.parent.parent.parent.join('libexec').expand_path
      httpchecker  = libexec.join('httpchecker')
      if httpchecker.exist?
        Kernel.exec(httpchecker.to_s, *ARGV)
      end
    end
  end


  receiver.desc 'HTTP API that caches and submits events'
  receiver.command :httpbroker do |httpbroker|
    httpbroker.passthrough = true
    httpbroker.action do |global_options, options, args|
      libexec = Pathname.new(__FILE__).parent.parent.parent.parent.join('libexec').expand_path
      httpbroker  = libexec.join('httpbroker')
      if httpbroker.exist?
        Kernel.exec(httpbroker.to_s, *ARGV)
      end
    end
  end
end


# # Nsca example line for a storage-device check:
# #[1393410685] PROCESS_SERVICE_CHECK_RESULT;db1.dev;STORAGE;0;Raid Set # 000 (800.0GB) is Normal.

# config_nr = config_env['nsca-receiver'] || {}

# pidfile = options.pidfile.nil? ?
#             (config_nr['pid_file'] || "/var/run/flapjack/#{exe}.pid") :
#             options.pidfile

# logfile = options.logfile.nil? ?
#             (config_nr['log_file'] || "/var/log/flapjack/#{exe}.log") :
#             options.logfile

# fifo = options.fifo.nil? ?
#          (config_nr['fifo'] || '/var/lib/nagios3/rw/nagios.cmd') :
#          options.fifo

# daemonize = options.daemonize.nil? ?
#               !!config_nr['daemonize'] :
#               options.daemonize
