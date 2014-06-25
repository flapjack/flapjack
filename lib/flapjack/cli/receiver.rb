#!/usr/bin/env ruby

require 'dante'
require 'redis'

require 'oj'
Oj.default_options = { :indent => 0, :mode => :strict }

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

        config = Flapjack::Configuration.new
        config.load(global_options[:config])
        @config_env = config.all

        if @config_env.nil? || @config_env.empty?
          puts "No config data for environment '#{FLAPJACK_ENV}' found in '#{global_options[:config]}'"
          exit 1
        end

        @redis_options = config.for_redis
      end

      # For nagios-receiver:
      #
      # nagios.cfg must contain the following perfdata templates for host and service data (modified from the default
      # to include hoststate / servicestate, and a fake service 'HOST' for hostperfdata, so that the
      # fields match up:
      #
      #   host_perfdata_file_template=[HOSTPERFDATA]\t$TIMET$\t$HOSTNAME$\tHOST\t$HOSTSTATE$\t$HOSTEXECUTIONTIME$\t$HOSTLATENCY$\t$HOSTOUTPUT$\t$HOSTPERFDATA$
      #
      #   service_perfdata_file_template=[SERVICEPERFDATA]\t$TIMET$\t$HOSTNAME$\t$SERVICEDESC$\t$SERVICESTATE$\t$SERVICEEXECUTIONTIME$\t$SERVICELATENCY$\t$SERVICEOUTPUT$\t$SERVICEPERFDATA$
      #

      def nagios_start
        if runner('nagios').daemon_running?
          puts "nagios-receiver is already running."
          exit 1
        else
          print "nagios-receiver starting..."
          runner('nagios').execute(:daemonize => @options[:daemonize]) do
            begin
              main(:fifo => @options[:fifo], :nagios => true)
            rescue Exception => e
              p e.message
              puts e.backtrace.join("\n")
            end
          end
          puts " done."
        end
      end

      def nagios_stop
        if runner('nagios').daemon_running?
          print "nagios-receiver stopping..."
          runner('nagios').execute(:kill => true)
          puts " done."
        else
          puts "nagios-receiver is not running."
          exit 1
        end
      end

      def nagios_restart
        print "nagios-receiver restarting..."
        runner('nagios').execute(:daemonize => true, :restart => true) do
          main(:fifo => @options[:fifo], :nagios => true)
        end
        puts " done."
      end

      def nagios_status
        config_runner = @config_env["nagios-receiver"] || {}
        pidfile = @options[:pidfile] || config_runner['pid_file'] ||
          "/var/run/flapjack/nagios-receiver.pid"
        uptime = (runner('nagios').daemon_running?) ? (Time.now - File.stat(pidfile).ctime) : 0
        if runner('nagios').daemon_running?
          puts "nagios-receiver is running: #{uptime}"
        else
          puts "nagios-receiver is not running"
          exit 3
        end
      end

      def nsca_start
        if runner('nsca').daemon_running?
          puts "nsca-receiver is already running."
          exit 1
        else
          print "nsca-receiver starting..."
          runner('nsca').execute(:daemonize => @options[:daemonize]) do
            main(:fifo => @options[:fifo], :nsca => true)
          end
          puts " done."
        end
      end

      def nsca_stop
        if runner('nsca').daemon_running?
          print "nsca-receiver stopping..."
          runner('nsca').execute(:kill => true)
          puts " done."
        else
          puts "nsca-receiver is not running."
          exit 1
        end
      end

      def nsca_restart
        print "nsca-receiver restarting..."
        runner('nsca').execute(:daemonize => true, :restart => true) do
          main(:fifo => @options[:fifo], :nsca => true)
        end
        puts " done."
      end

      def nsca_status
        config_runner = @config_env["nsca-receiver"] || {}

        pidfile = @options[:pidfile] || config_runner['pid_file'] ||
          "/var/run/flapjack/nsca-receiver.pid"

        uptime = (runner('nsca').daemon_running?) ? (Time.now - File.stat(pidfile).ctime) : 0
        if runner('nsca').daemon_running?
          puts "nsca-receiver is running: #{uptime}"
        else
          puts "nsca-receiver is not running"
          exit 3
        end
      end

      def json
        json_feeder(:from => @options[:from])
      end

      def mirror
        mirror_receive(:source => @options[:source],
          :all => @options[:all], :follow => @options[:follow],
          :last => @options[:last], :time => @options[:time])
      end

      private

      def redis
        @redis ||= Redis.new(@redis_options)
      end

      def runner(type)
        return @runner if @runner

        config_runner = @config_env["#{type}-receiver"] || {}

        pidfile = @options[:pidfile].nil? ?
                    (config_runner['pid_file'] || "/var/run/flapjack/#{type}-receiver.pid") :
                    @options[:pidfile]

        logfile = @options[:logfile].nil? ?
                    (config_runner['log_file'] || "/var/log/flapjack/#{type}-receiver.log") :
                    @options[:logfile]

        @runner = Dante::Runner.new("#{type}-receiver", :pid_path => pidfile,
          :log_path => logfile)
        @runner
      end

      def process_input(opts)
        config_rec = if opts[:nagios]
          @config_env['nagios-receiver'] || {}
        elsif opts[:nsca]
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

            if opts[:nagios]

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

            elsif opts[:nsca]

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
          process_input(:fifo => fifo, :nagios => opts[:nagios], :nsca => opts[:nsca])
          puts "Whoops with the fifo, restarting main loop in 10 seconds"
          sleep 10
        end
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
          puts "No file provided, and STDIN is from terminal! Exiting..."
          exit(1)
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
          puts "one or both of --follow or --all is required"
          exit 1
        end

        source_redis = Redis.new(:url => opts[:source])

        archives = mirror_get_archive_keys_stats(source_redis)
        raise "found no archives!" unless archives && archives.length > 0

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
          archive_key = archives[0][:name]
          cursor      = -1
        when opts[:last], opts[:time]
          raise "Sorry, unimplemented"
        else
          # wait for the next event to be archived, so point the cursor at a non-existant
          # slot in the list, the one before the 0'th
          archive_key = archives[-1][:name]
          cursor      = -1 - archives[-1][:size]
        end

        puts archive_key

        loop do
          new_archive_key = false
          # something to read at cursor?
          event = source_redis.lindex(archive_key, cursor)
          if event
            Flapjack::Data::Event.add(event, :redis => redis)
            events_sent += 1
            print "#{events_sent} " if events_sent % 1000 == 0
            cursor -= 1
          else
            puts "\narchive key: #{archive_key}, cursor: #{cursor}"
            # do we need to look at the next archive bucket?
            archives = mirror_get_archive_keys_stats(source_redis)
            i = archives.index {|a| a[:name] == archive_key }
            if archives[i][:size] = (cursor.abs + 1)
              if archives[i + 1]
                archive_key = archives[i + 1][:name]
                puts archive_key
                cursor = -1
                new_archive_key = true
              else
                return unless opts[:follow]
              end
            end
            sleep 1 unless new_archive_key
          end
        end
      end

      def mirror_get_archive_keys_stats(source_redis)
        source_redis.keys("events_archive:*").sort.map {|a|
          { :name => a,
            :size => source_redis.llen(a) }
        }
      end

    end
  end
end

desc 'Receive events from external systems and send them to Flapjack'
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

    # Details on the wiki: https://github.com/flapjack/flapjack/wiki/USING#configuring-nagios
    # '

    nagios.command :start do |start|

      start.switch [:d, 'daemonize'], :desc => 'Daemonize',
        :default_value => true

      start.flag   [:p, 'pidfile'],   :desc => 'PATH of the pidfile to write to'

      start.flag   [:l, 'logfile'],   :desc => 'PATH of the logfile to write to'

      start.flag   [:f, 'fifo'],      :desc => 'PATH of the nagios perfdata named pipe'

      start.action do |global_options,options,args|
        receiver = Flapjack::CLI::Receiver.new(global_options, options)
        receiver.nagios_start
      end
    end

    nagios.command :stop do |stop|

      stop.flag   [:p, 'pidfile'],   :desc => 'PATH of the pidfile to write to'

      stop.flag   [:l, 'logfile'],   :desc => 'PATH of the logfile to write to'

      stop.action do |global_options,options,args|
        receiver = Flapjack::CLI::Receiver.new(global_options, options)
        receiver.nagios_stop
      end
    end

    nagios.command :restart do |restart|

      restart.flag   [:p, 'pidfile'],   :desc => 'PATH of the pidfile to write to'

      restart.flag   [:l, 'logfile'],   :desc => 'PATH of the logfile to write to'

      restart.flag   [:f, 'fifo'],      :desc => 'PATH of the nagios perfdata named pipe'

      restart.action do |global_options,options,args|
        receiver = Flapjack::CLI::Receiver.new(global_options, options)
        receiver.nagios_restart
      end
    end

    nagios.command :status do |status|

      status.flag   [:p, 'pidfile'],   :desc => 'PATH of the pidfile to write to'

      status.flag   [:l, 'logfile'],   :desc => 'PATH of the logfile to write to'

      status.action do |global_options,options,args|
        receiver = Flapjack::CLI::Receiver.new(global_options, options)
        receiver.nagios_status
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

      # Details on the wiki: https://github.com/flapjack/flapjack/wiki/USING#XXX
      # '

      start.switch [:d, 'daemonize'], :desc => 'Daemonize',
        :default_value => true

      start.flag   [:p, 'pidfile'],   :desc => 'PATH of the pidfile to write to'

      start.flag   [:l, 'logfile'],   :desc => 'PATH of the logfile to write to'

      start.flag   [:f, 'fifo'],      :desc => 'PATH of the nagios perfdata named pipe'

      start.action do |global_options,options,args|
        receiver = Flapjack::CLI::Receiver.new(global_options, options)
        receiver.nsca_start
      end
    end

    nsca.command :stop do |stop|

      stop.flag   [:p, 'pidfile'],   :desc => 'PATH of the pidfile to write to'

      stop.flag   [:l, 'logfile'],   :desc => 'PATH of the logfile to write to'

      stop.action do |global_options,options,args|
        receiver = Flapjack::CLI::Receiver.new(global_options, options)
        receiver.nsca_stop
      end
    end

    nsca.command :restart do |restart|

      restart.flag   [:p, 'pidfile'],   :desc => 'PATH of the pidfile to write to'

      restart.flag   [:l, 'logfile'],   :desc => 'PATH of the logfile to write to'

      restart.flag   [:f, 'fifo'],      :desc => 'PATH of the nagios perfdata named pipe'

      restart.action do |global_options,options,args|
        receiver = Flapjack::CLI::Receiver.new(global_options, options)
        receiver.nsca_restart
      end
    end

    nsca.command :status do |status|

      status.flag   [:p, 'pidfile'],   :desc => 'PATH of the pidfile to write to'

      status.flag   [:l, 'logfile'],   :desc => 'PATH of the logfile to write to'

      status.action do |global_options,options,args|
        receiver = Flapjack::CLI::Receiver.new(global_options, options)
        receiver.nsca_status
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

    mirror.flag     [:s, 'source'], :desc => 'URL of source redis database, eg redis://localhost:6379/0',
      :required => true

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
