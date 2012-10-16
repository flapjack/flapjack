
namespace :profile do

  require 'flapjack/configuration'
  require 'flapjack/executive'

  FLAPJACK_ENV    = 'profile'
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

    desc "profile executive with rubyprof"
    task :executive do
      config, redis_opts = load_config
      exec = Flapjack::Executive.new
      exec.bootstrap(:redis => redis_opts, :config => config_env['executive'])
      t = rubyprof_profile('executive_profile.txt') { exec.main }

      # TODO add some events

      exec.stop
      exec.add_shutdown_event(:redis => Redis.new(redis_options.merge(:driver => 'ruby')))
      t.join
    end

  end

  # namespace :perftools do
  #   task :executive do

  #   end
  # end

end