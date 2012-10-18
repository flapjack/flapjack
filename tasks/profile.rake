namespace :profile do

  require 'flapjack/configuration'
  require 'flapjack/executive'

  FLAPJACK_ROOT   = File.join(File.dirname(__FILE__), '..')
  FLAPJACK_CONFIG = File.join(FLAPJACK_ROOT, 'etc', 'flapjack_profile.yaml')

  def load_config
    config_env = Flapjack::Configuration.new.load(FLAPJACK_CONFIG)
    if config_env.nil? || config_env.empty?
      puts "No config data for environment '#{FLAPJACK_ENV}' found in '#{FLAPJACK_CONFIG}'"
      exit(false)
    end

    config_env
  end

  def redis_options(config)
    redis_host = config['redis']['host'] || '127.0.0.1'
    redis_port = config['redis']['port'] || 6379
    redis_path = config['redis']['path'] || nil
    redis_db   = config['redis']['db']   || 0

    if redis_path
      { :db => redis_db, :path => redis_path }
    else
      { :db => redis_db, :host => redis_host, :port => redis_port }
    end
  end

  def profile_coordinator(profiler_klass)
    config = load_config
    coordinator = Flapjack::Coordinator.new(config)

    t = profiler_klass.profile("coordinator_profile.txt") {
      coordinator.start(:daemonize => false, :signals => false)
    }

    yield

    coordinator.stop
    t.join
  end

  def profile_pikelet(profiler_klass, klass, config_key)
    config_env = load_config
    redis_opts = redis_options(config_env)
    pikelet = klass.new
    pikelet.bootstrap(:config => config_env[config_key],
      :redis_config => redis_opts))
    t = profiler_klass.profile("#{config_key}_profile.txt") { pikelet.main }

    yield

    pikelet.stop
    redis = Redis.new(redis_opts.merge(:driver => 'ruby'))
    pikelet.add_shutdown_event(:redis => redis)
    redis.quit
    t.join
  end

  def profile_resque(profiler_klass, klass, config_key)
    config_env = load_config
    pool = Flapjack::RedisPool.new(:config => @redis_options)
    ::Resque.redis = pool
    worker = EM::Resque::Worker.new(config_env[config_key]['queue'])
    t = profiler_klass.profile("#{config_key}_profile.txt") { worker.work }

    yield

    worker.shutdown
    t.join
    pool.empty!
  end

  def profile_thin(profiler_klass, klass, config_key)
    config_env, redis_opts = load_config
    klass.bootstrap(:config => config, :redis_config => redis_options(config_env))

    Thin::Logging.silent = true
    server = Thin::Server.new('0.0.0.0', klass.instance_variable_get('@port'),
               klass, :signals => false)

    t = profiler_klass.profile("#{config_key}_profile.txt") {
      server.start
    }

    yield

    server.stop!
    t.join
  end

  namespace :rubyprof do

    require 'ruby-prof'

    class RubyprofProfiler

      def self.profile(output_filename)
        Thread.new {
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
        }
      end

    end

    desc "profile multiple components running through coordinator with rubyprof"
    task :coordinator do
      FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'profile'
      profile_coordinator(RubyprofProfiler) {
        # TODO make things happen
      }
    end

    desc "profile executive with rubyprof"
    task :executive do
      FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'profile'
      profile_pikelet(RubyprofProfiler, Flapjack::Executive, 'executive') {
        # TODO add some events
      }
    end

    # NB: you'll need to access a real jabber server for this; if external events come in
    # from that then runs will not necessarily be comparable
    desc :jabber do
      FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'profile'
      profile_pikelet(RubyprofProfiler, Flapjack::Jabber, 'jabber_gateway') {
        # TODO add some notifications
      }
    end

    # NB: you'll need an external email server set up for this (whether it's mailtrap
    # or a real server)
    desc "profile email notifier with rubyprof"
    task :email do
      FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'profile'
      profile_resque(RubyprofProfiler, Flapjack::Notification::Email, 'email_notifier') {
        # TODO add some notifications
      }
    end

    desc "profile web server with rubyprof"
    task :web do
      FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'profile'
      profile_thin(RubyprofProfiler, Flapjack::Web, 'web') {
        # TODO add some web requests
      }
    end

  end

end