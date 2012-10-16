
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

    redis_host = config_env['redis']['host'] || '127.0.0.1'
    redis_port = config_env['redis']['port'] || 6379
    redis_path = config_env['redis']['path'] || nil
    redis_db   = config_env['redis']['db']   || 0

    redis_options = if redis_path
      { :db => redis_db, :path => redis_path }
    else
      { :db => redis_db, :host => redis_host, :port => redis_port }
    end

    return config_env, redis_options
  end

  namespace :rubyprof do

    require 'ruby-prof'

    def rubyprof_profile(filename)
      Thread.new {
        RubyProf.start
        EM.synchrony do
          yield
          EM.stop
        end
        result = RubyProf.stop
        printer = RubyProf::FlatPrinter.new(result)
        File.open(filename, 'w') {|f|
          printer.print(f)
        }
      }
    end

    def profile_pikelet(klass, config_key)
      config, redis_opts = load_config
      pikelet = klass.new
      pikelet.bootstrap(:redis => redis_opts, :config => config_env[config_key])
      t = rubyprof_profile("#{config_key}_profile.txt") { pikelet.main }

      yield

      pikelet.stop
      pikelet.add_shutdown_event(:redis => Redis.new(redis_options.merge(:driver => 'ruby')))
      t.join
    end

    def profile_resque(klass, config_key)
      config, redis_opts = load_config
      worker = EM::Resque::Worker.new(config_env[config_key]['queue'])
      t = rubyprof_profile("#{config_key}_profile.txt") { worker.work }

      yield

      worker.shutdown
      t.join
    end

    def profile_thin(klass, config_key)
      config, redis_opts = load_config


      t = rubyprof_profile("#{config_key}_profile.txt") { }

      yield

      pikelet.stop
      t.join
    end

    desc "profile executive with rubyprof"
    task :executive do
      FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'profile'
      profile_pikelet(Flapjack::Executive, 'executive') {
        # TODO add some events
      }
    end

    # NB: you'll need to access a real jabber server for this; if external events come in
    # from that then runs will not necessarily be comparable
    desc :jabber do
      FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'profile'
      profile_pikelet(Flapjack::Jabber, 'jabber_gateway') {
        # TODO add some notifications
      }
    end

    # NB: you'll need an external email server set up for this (whether it's mailtrap
    # or a real server)
    desc "profile email notifier with rubyprof"
    task :email do
      FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'profile'
      profile_resque(Flapjack::Notification::Email, 'email_notifier') {
        # TODO add some notifications
      }
    end

    desc "profile web server with rubyprof"
    task :web do
      FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'profile'
      profile_thin(Flapjack::Web, 'web') {
        # TODO add some web requests
      }
    end

  end

end