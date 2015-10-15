#!/usr/bin/env ruby

require 'redis'

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

        if @global_options[:'force-utf8']
          Encoding.default_external = 'UTF-8'
          Encoding.default_internal = 'UTF-8'
        end

        @config = Flapjack::Configuration.new
        @config.load(global_options[:config])
        @config_env = @config.all

        if @config_env.nil? || @config_env.empty?
          unless 'mirror'.eql?(@options[:type])
            exit_now! "No config data found in '#{global_options[:config]}'"
          end
        end

        unless 'mirror'.eql?(@options[:type])
          Flapjack::RedisProxy.config = @config.for_redis
          Zermelo.redis = Flapjack.redis
        end

        @redis_options = @config.for_redis
      end

      def start
        puts "#{@options[:type]}-receiver starting..."
        begin
          main(:fifo => @options[:fifo], :type => @options[:type])
        rescue Exception => e
          p e.message
          puts e.backtrace.join("\n")
        end
        puts " done."
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
        @redis ||= Redis.new(@redis_options)
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
            Flapjack::Data::Event.push('events', event)
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

      def json_feeder(opts = {})
        require 'json/stream'

        input = if opts[:from]
          File.open(opts[:from]) # Explodes if file does not exist.
        elsif !'java'.eql?(RUBY_PLATFORM) && STDIN.tty?
          # tty check isn't working under JRuby, assume STDIN is OK to use
          # https://github.com/jruby/jruby/issues/1332
          exit_now! "No file provided, and STDIN is from terminal! Exiting..."
        else
          STDIN
        end

        # Sit and churn through the input stream until a valid JSON blob has been assembled.
        # This handles both the case of a process sending a single JSON and then exiting
        # (eg. cat foo.json | bin/flapjack receiver json) *and* a longer-running process spitting
        # out events (eg. /usr/bin/slow-event-feed | bin/flapjack receiver json)
        #
        # @data is a stack, but @stack is used by the Parser class
        parser = JSON::Stream::Parser.new do
          start_document do
            @data = []
            @keys = []
            @result = nil
          end

          end_document {
            # interfering with json-stream's "one object per stream" model,
            # but it errors without this
            @state = :start_document
          }

          start_object do
            @data.push({})
          end

          end_object do
            node = @data.pop

            if @data.size > 0
              top = @data.last
              case top
              when Hash
                top[@keys.pop] = node
              when Array
                top << node
              end
            else
              errors = Flapjack::Data::Event.validation_errors_for_hash(node)
              if errors.empty?
                Flapjack::Data::Event.push('events', node)
                puts "Enqueued event data, #{node.inspect}"
              else
                puts "Invalid event data received, #{errors.join(', ')} #{node.inspect}"
              end
            end
          end

          start_array do
            @data.push([])
          end

          end_array do
            node = @data.pop
            if @data.size > 0
              top = @data.last
              case top
              when Hash
                top[@keys.pop] = node
              when Array
                top << node
              end
            end
          end

          key do |k|
            @keys << k
          end

          value do |v|
            top = @data.last
            case top
            when Hash
              top[@keys.pop] = v
            when Array
              top << v
            else
              @data << v
            end
          end
        end

        while data = input.read(4096)
          parser << data
        end

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
          Redis.new(dest_addr.merge(:driver => :hiredis))
        when String
          Redis.new(:url => dest_addr, :driver => :hiredis)
        else
          exit_now! "could not understand destination Redis config"
        end

        Flapjack::RedisProxy.config = dest_redis
        Zermelo.redis = Flapjack.redis

        archives = mirror_get_archive_keys_stats(:source => source_redis)
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
            event, errors = Flapjack::Data::Event.parse_and_validate(event_json)

            if !errors.nil? && !errors.empty?
              Flapjack.logger.error {
                error_str = errors.nil? ? '' : errors.join(', ')
                "Invalid event data received, #{error_str} #{event.inspect}"
              }
            elsif (include_re.nil? ||
              (include_re === "#{event['entity']}:#{event['check']}"))

              Flapjack::Data::Event.add(event)
              events_sent += 1
              print "#{events_sent} " if events_sent % 1000 == 0
            end
            cursor -= 1
            next
          end

          archives = mirror_get_archive_keys_stats(:source => source_redis).select {|a|
            a[:size] > 0
          }

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

      def mirror_get_archive_keys_stats(opts = {})
        source_redis = opts[:source]
        source_redis.smembers("known_events_archive_keys").sort.collect do |eak|
          {:name => eak, :size => source_redis.llen(eak)}
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
    nagios.flag   [:f, 'fifo'],      :desc => 'PATH of the nagios perfdata named pipe'

    nagios.action do |global_options,options,args|
      options.merge!(:type => 'nagios')
      receiver_cli = Flapjack::CLI::Receiver.new(global_options, options)
      receiver_cli.start
    end
  end

  receiver.desc 'NSCA receiver'
  #receiver.arg_name 'Turn Nagios passive check results into Flapjack events'
  receiver.command :nsca do |nsca|

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
    nsca.flag   [:f, 'fifo'],      :desc => 'PATH of the nagios perfdata named pipe'

    nsca.action do |global_options,options,args|
      options.merge!(:type => 'nsca')
      cli_receiver = Flapjack::CLI::Receiver.new(global_options, options)
      cli_receiver.start
    end

  end

  receiver.desc 'JSON receiver'
  receiver.command :json do |json|
    json.flag [:f, 'from'],     :desc => 'PATH of the file to process [STDIN]'

    json.action do |global_options,options,args|
      cli_receiver = Flapjack::CLI::Receiver.new(global_options, options)
      cli_receiver.json
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
      else
        exit_now! "Oneoff event submitter doesn't exist"
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
      else
        exit_now! "HTTP checker doesn't exist"
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
      else
        exit_now! "HTTP broker doesn't exist"
      end
    end
  end

  receiver.desc 'HTTP API that caches and submits Cloudwatch events'
  receiver.command :cloudwatchbroker do |cloudwatchbroker|
    cloudwatchbroker.passthrough = true
    cloudwatchbroker.action do |global_options, options, args|
      libexec = Pathname.new(__FILE__).parent.parent.parent.parent.join('libexec').expand_path
      cloudwatchbroker  = libexec.join('httpbroker')
      if cloudwatchbroker.exist?
        Kernel.exec(cloudwatchbroker.to_s, *(ARGV + ['--format=sns']))
      else
        exit_now! "HTTP broker doesn't exist"
      end
    end
  end

end


# # Nsca example line for a storage-device check:
# #[1393410685] PROCESS_SERVICE_CHECK_RESULT;db1.dev;STORAGE;0;Raid Set # 000 (800.0GB) is Normal.

# config_nr = config_env['nsca-receiver'] || {}

# logfile = options.logfile.nil? ?
#             (config_nr['log_file'] || "/var/log/flapjack/#{exe}.log") :
#             options.logfile

# fifo = options.fifo.nil? ?
#          (config_nr['fifo'] || '/var/lib/nagios3/rw/nagios.cmd') :
#          options.fifo
