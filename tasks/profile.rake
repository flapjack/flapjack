namespace :profile do

  require 'flapjack/configuration'
  require 'flapjack/executive'

  require 'flapjack/data/event'
  require 'flapjack/data/message'

  FLAPJACK_ROOT   = File.join(File.dirname(__FILE__), '..')
  FLAPJACK_CONFIG = File.join(FLAPJACK_ROOT, 'etc', 'flapjack_profile.yaml')

  FLAPJACK_PROFILER = ENV['FLAPJACK_PROFILER'] || 'rubyprof'
  port = ENV['FLAPJACK_PROFILER'].to_i
  FLAPJACK_PORT = ((port > 1024) && (port <= 65535)) ? port : 8075

  require (FLAPJACK_PROFILER =~ /^perftools$/i) ? 'perftools' : 'rubyprof'

  REPETITIONS     = 100

  def profile(output_filename)
    Thread.new {
      if FLAPJACK_PROFILER =~ /^perftools$/i
        PerfTools::CpuProfiler.start(output_filename) do
          EM.synchrony do
            yield
            EM.stop
          end
        end
      else
        RubyProf.start
        EM.synchrony do
          yield
          EM.stop
        end
        result = RubyProf.stop
        printer = RubyProf::FlatPrinter.new(result)
        File.open(output_filename, 'w') {|f|
          printer.print(f)
        }
      end
    }
  end

  def load_config
    config_env, redis_options = Flapjack::Configuration.new.load(FLAPJACK_CONFIG)
    if config_env.nil? || config_env.empty?
      puts "No config data for environment '#{FLAPJACK_ENV}' found in '#{FLAPJACK_CONFIG}'"
      exit(false)
    end

    return config_env, redis_options
  end

  def check_db_empty(redis_options)
    redis = Redis.new(redis_options)

    # DBSIZE can return > 0 with expired keys -- but that's fine, we only
    # want to run against an explicitly empty DB. If this fails against the
    # intended Redis DB, they can FLUSHDB it manually
    db_size = redis.dbsize.to_i
    if db_size > 0
      db = redis_options['db']
      puts "Redis database has a non-zero DBSIZE (#{db_size}); profiling will destroy data."
      puts "Use 'SELECT #{db}; FLUSHDB' in redis-cli if you really want to use this database."
      puts "[redis options] #{options[:redis].inspect}"
      puts "Exiting..."
      exit(false)
    end
  end

  def empty_db(redis_options)
    redis = Redis.new(redis_options)
    redis.flushdb
  end

  # this adds a default entity and contact, so that the profiling methods
  # will actually trigger enough code to be useful
  def setup_baseline_data(options = {})

    # FIXME

  end

  def profile_coordinator
    config_env, redis_options = load_config
    check_db_empty(redis_options)

    # TODO set up entity, contact

    coordinator = Flapjack::Coordinator.new(config, redis_options)

    t = profile("tmp/profile_coordinator.txt") {
      coordinator.start(:daemonize => false, :signals => false)
    }

    yield

    coordinator.stop
    t.join
    empty_db(redis_options)
  end

  def profile_pikelet(klass, config_key)
    config_env, redis_options = load_config
    check_db_empty(redis_options)

    # TODO set up entity, contact

    pikelet = klass.new
    pikelet.bootstrap(:config => config_env[config_key],
      :redis_config => redis_options)

    t = profile("tmp/profile_#{config_key}.txt") { pikelet.main }

    yield

    pikelet.stop
    redis = Redis.new(redis_opts.merge(:driver => 'ruby'))
    pikelet.add_shutdown_event(:redis => redis)
    redis.quit
    t.join
    empty_db(redis_options)
  end

  def profile_resque(klass, config_key)
    config_env, redis_options = load_config
    check_db_empty(redis_options)

    # TODO set up entity, contact

    pool = Flapjack::RedisPool.new(:config => redis_options)
    ::Resque.redis = pool
    worker = EM::Resque::Worker.new(config_env[config_key]['queue'])

    t = profile("tmp/profile_#{config_key}.txt") { worker.work }

    yield

    worker.shutdown
    t.join
    pool.empty!
    empty_db(redis_options)
  end

  def profile_thin(klass, config_key)
    config_env, redis_options = load_config
    check_db_empty(redis_options)

    # TODO set up entity, contact

    klass.bootstrap(:config => config, :redis_config => redis_options)

    Thin::Logging.silent = true
    server = Thin::Server.new('0.0.0.0', FLAPJACK_PORT, klass, :signals => false)

    t = profile("tmp/profile_#{config_key}.txt") {
      server.start
    }

    yield

    server.stop!
    t.join
    empty_db(redis_options)
  end

  desc "profile multiple components running through coordinator with rubyprof"
  task :coordinator do
    FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'profile'
    profile_coordinator {
      (1..REPETITIONS).times do |n|
        Flapjack::Data::Event.create({'entity'  => 'clientx-app-01',
                                      'check'   => 'ping',
                                      'type'    => 'service',
                                      'state'   => n ? 'ok' : 'critical',
                                      'summary' => 'testing'}, :redis => redis)
      end
    }
  end

  desc "profile executive with rubyprof"
  task :executive do
    FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'profile'
    profile_pikelet(Flapjack::Executive, 'executive') {
      (1..REPETITIONS).times do |n|
        Flapjack::Data::Event.create({'entity'  => 'clientx-app-01',
                                      'check'   => 'ping',
                                      'type'    => 'service',
                                      'state'   => n ? 'ok' : 'critical',
                                      'summary' => 'testing'}, :redis => redis)
      end
    }
  end

  # NB: you'll need to access a real jabber server for this; if external events come in
  # from that then runs will not be comparable
  desc "profile jabber gateway with rubyprof"
  task :jabber do
    FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'profile'
    profile_pikelet(Flapjack::Jabber, 'jabber_gateway') {
      (1..REPETITIONS).times do
        # TODO add some messages
        # Flapjack::Data::Message.create( )
      end
    }
  end

  # NB: you'll need an external email server set up for this (whether it's mailtrap
  # or a real server)
  desc "profile email notifier with rubyprof"
  task :email do
    FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'profile'
    profile_resque(Flapjack::Notification::Email, 'email_notifier') {
      (1..REPETITIONS).times do
        # TODO add some messages
        # Flapjack::Data::Message.create( )
      end
    }
  end

  # Of course, if external requests come to this server then different runs will not
  # be comparable
  desc "profile web server with rubyprof"
  task :web do
    FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'profile'
    profile_thin(Flapjack::Web, 'web') {
      # TODO add some web requests
    }
  end

end