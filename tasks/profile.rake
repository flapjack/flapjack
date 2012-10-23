namespace :profile do

  require 'flapjack/configuration'
  require 'flapjack/executive'

  require 'flapjack/data/event'
  require 'flapjack/data/message'

  FLAPJACK_ROOT   = File.join(File.dirname(__FILE__), '..')
  FLAPJACK_CONFIG = File.join(FLAPJACK_ROOT, 'etc', 'flapjack_config.yaml')

  FLAPJACK_PROFILER = ENV['FLAPJACK_PROFILER'] || 'rubyprof'
  port = ENV['FLAPJACK_PROFILER'].to_i
  FLAPJACK_PORT = ((port > 1024) && (port <= 65535)) ? port : 8075

  REPETITIONS     = 100

  require (FLAPJACK_PROFILER =~ /^perftools$/i) ? 'perftools' : 'ruby-prof'

  def profile(name)
    output_filename = File.join('tmp', "profile_#{name}.txt")
    Fiber.new {
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
    }.resume
  end

  def load_config
    config_env, redis_options = Flapjack::Configuration.new.
                                  load(FLAPJACK_CONFIG)
    if config_env.nil? || config_env.empty?
      puts "No config data for environment '#{FLAPJACK_ENV}' " +
        "found in '#{FLAPJACK_CONFIG}'"
      exit(false)
    end

    return config_env, redis_options
  end

  def check_db_empty(options = {})
    redis = options[:redis]
    redis_options = options[:redis_options]

    # DBSIZE can return > 0 with expired keys -- but that's fine, we only
    # want to run against an explicitly empty DB. If this fails against the
    # intended Redis DB, the user can FLUSHDB it manually
    db_size = redis.dbsize.to_i
    if db_size > 0
      db = redis_options['db']
      puts "The Redis database has a non-zero DBSIZE (#{db_size}) -- "
           "profiling will destroy data. Use 'SELECT #{db}; FLUSHDB' in " +
           'redis-cli if you want to profile using this database.'
      puts "[redis options] #{options[:redis].inspect}\nExiting..."
      exit(false)
    end
  end

  def empty_db(options = {})
    redis = options[:redis]
    redis.flushdb
  end

  # this adds a default entity and contact, so that the profiling methods
  # will actually trigger enough code to be useful
  def setup_baseline_data(options = {})
    entity = {"id"        => "2000",
              "name"      => "clientx-app-01",
              "contacts"  => ["1000"]}

    Flapjack::Data::Entity.add(entity, :redis => options[:redis])

    contact = {'id'         => '1000',
               'first_name' => 'John',
               'last_name'  => 'Smith',
               'email'      => 'jsmith@example.com',
               'media'      => {
                 'email' => 'jsmith@example.com'
               }}

    Flapjack::Data::Contact.add(contact, :redis => options[:redis])
  end

  def profile_coordinator(config, redis_options)
    redis = Redis.new(redis_options.merge(:driver => 'ruby'))
    check_db_empty(:redis => redis, :redis_options => redis_options)
    setup_baseline_data(:redis => redis)

    coordinator = Flapjack::Coordinator.new(config, redis_options)

    profile('coordinator') {
      coordinator.start(:daemonize => false, :signals => false)
    }

    yield if block_given?

    coordinator.stop
    empty_db(:redis => redis)
    redis.quit
  end

  def profile_pikelet(klass, name, config, redis_options)
    redis = Redis.new(redis_options.merge(:driver => 'ruby'))
    check_db_empty(:redis => redis, :redis_options => redis_options)
    setup_baseline_data(:redis => redis)

    pikelet = klass.new
    pikelet.bootstrap(:config => config[config_key],
      :redis_config => redis_options)

    profile(name) { pikelet.main }

    yield if block_given?

    pikelet.stop
    pikelet.add_shutdown_event(:redis => redis)
    empty_db(:redis => redis)
    redis.quit
  end

  def profile_resque(klass, name, config, redis_options)
    redis = Redis.new(redis_options.merge(:driver => 'ruby'))
    check_db_empty(:redis => redis, :redis_options => redis_options)
    setup_baseline_data(:redis => redis)

    pool = Flapjack::RedisPool.new(:config => redis_options)
    ::Resque.redis = pool
    worker = EM::Resque::Worker.new(config_env[config_key]['queue'])

    profile(name) { worker.work }

    yield if block_given?

    worker.shutdown
    pool.empty!
    empty_db(:redis => redis)
    redis.quit
  end

  def profile_thin(klass, name, config, redis_options)
    redis = Redis.new(redis_options.merge(:driver => 'ruby'))
    check_db_empty(:redis => redis, :redis_options => redis_options)
    setup_baseline_data(:redis => redis)

    klass.bootstrap(:config => config, :redis_config => redis_options)

    Thin::Logging.silent = true
    server = Thin::Server.new('0.0.0.0', FLAPJACK_PORT,
      klass, :signals => false)

    profile(name) {
      server.start
    }

    yield if block_given?

    server.stop!
    empty_db(:redis => redis)
    redis.quit
  end

  desc "profile startup of running through coordinator with rubyprof"
  task :coordinator do
    FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'profile'
    config_env, redis_options = load_config
    profile_coordinator(config_env, redis)
  end

  desc "profile executive with rubyprof"
  task :executive do
    FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'profile'
    config_env, redis_options = load_config
    profile_pikelet(Flapjack::Executive, 'executive', config_env['executive'],
      redis_options) {
      REPETITIONS.times do |n|
        Flapjack::Data::Event.add({'entity'  => 'clientx-app-01',
                                   'check'   => 'ping',
                                   'type'    => 'service',
                                   'state'   => (n ? 'ok' : 'critical'),
                                   'summary' => 'testing'},
                                  :redis => redis)
      end
    }
  end

  # NB: you'll need to access a real jabber server for this; if external events
  # come in from that then runs will not be comparable
  desc "profile jabber gateway with rubyprof"
  task :jabber do
    FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'profile'
    config_env, redis_options = load_config
    profile_pikelet(Flapjack::Jabber, 'jabber', config_env['jabber_gateway'],
      redis_options) {

      EM.synchrony do

        redis = Flapjack::RedisPool.new(:config => redis_options)

        event = Flapjack::Data::Event.new('type'    => 'service',
                                          'state'   => 'critical',
                                          'summary' => '100% packet loss',
                                          'entity'  => 'clientx-app-01',
                                          'check'   => 'ping')
        notification = Flapjack::Data::Notification.for_event(event)

        contact = Flapjack::Data::Contact.for_id('1000')

        REPETITIONS.times do |n|
          notification.messages(:contacts => [contact]).each do |msg|
            contents = msg.contents
            contents['event_count'] = n
            redis.rpush(config_env['jabber_gateway']['queue'],
              Yajl::Encoder.encode(contents))
          end
        end

        redis.empty!
    end

    }
  end

  # NB: you'll need an external email server set up for this (whether it's
  # mailtrap or a real server)
  desc "profile email notifier with rubyprof"
  task :email do
    FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'profile'
    config_env, redis_options = load_config
    profile_resque(Flapjack::Notification::Email, 'email',
      config_env['email_notifier'], redis_options) {

      event = Flapjack::Data::Event.new('type'    => 'service',
                                        'state'   => 'critical',
                                        'summary' => '100% packet loss',
                                        'entity'  => 'clientx-app-01',
                                        'check'   => 'ping')
      notification = Flapjack::Data::Notification.for_event(event)

      contact = Flapjack::Data::Contact.for_id('1000')

      REPETITIONS.times do
        notification.messages(:contacts => [contact]).each do |msg|
          Resque.enqueue_to(config_env['email_notifier']['queue'],
            Flapjack::Notification::Email, msg.contents)
        end
      end
    }
  end

  # Of course, if external requests come to this server then different runs will
  # not be comparable
  desc "profile web server with rubyprof"
  task :web do

    require 'em-synchrony/em-http'
    require 'flapjack/web'

    FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'profile'
    config_env, redis_options = load_config
    profile_thin(Flapjack::Web, 'web', config_env['web'], redis_options) {

      EM.synchrony do
        multi = EventMachine::Synchrony::Multi.new
        REPETITIONS.times do |n|
          req = EventMachine::HttpRequest.
            new("http://127.0.0.1:#{FLAPJACK_PORT}/")
          multi.add :"flapjack_#{n}", req.aget
        end
        res = multi.perform
      end

    }
  end

end