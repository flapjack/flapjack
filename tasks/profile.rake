namespace :profile do

  require 'fileutils'
  require 'flapjack/configuration'

  FLAPJACK_ROOT   = File.join(File.dirname(__FILE__), '..')
  FLAPJACK_CONFIG = File.join(FLAPJACK_ROOT, 'etc', 'flapjack_config.yaml')

  FLAPJACK_PROFILER = ENV['FLAPJACK_PROFILER'] || 'rubyprof'
  port = ENV['FLAPJACK_PROFILER'].to_i
  FLAPJACK_PORT = ((port > 1024) && (port <= 65535)) ? port : 8075

  REPETITIONS     = 10

  require 'ruby-prof'

  def profile_pikelet(klass, name, config, redis_options, &block)
    redis = Redis.new(redis_options.merge(:driver => 'ruby'))
    check_db_empty(:redis => redis, :redis_options => redis_options)
    setup_baseline_data(:redis => redis)

    EM.synchrony do
      RubyProf.start
      pikelet = klass.new
      pikelet.bootstrap(:config => config,
        :redis_config => redis_options)

      EM.defer(block, proc {
        pikelet.stop
        pikelet.add_shutdown_event(:redis => redis)
      })

      pikelet.main
      pikelet.cleanup
      result = RubyProf.stop
      result.eliminate_methods!([/Class::Thread/, /Deferrable/])
      printer = RubyProf::MultiPrinter.new(result)
      output_dir = File.join('tmp', 'profiles')
      FileUtils.mkdir_p(output_dir)
      printer.print(:path => output_dir, :profile => name)
      EM.stop
    end

    empty_db(:redis => redis)
    redis.quit
  end

  def profile_thin(klass, name, config, redis_options, &block)
    redis = Redis.new(redis_options.merge(:driver => 'ruby'))
    check_db_empty(:redis => redis, :redis_options => redis_options)
    setup_baseline_data(:redis => redis)

    Thin::Logging.silent = true

    EM.synchrony do
      output_dir = File.join('tmp', 'profiles')
      FileUtils.mkdir_p(output_dir)

      profile_klass = Class.new(klass)
      profile_klass.instance_eval {
        before do
          RubyProf.send( (profile_klass.class_variable_defined?('@@profiling') ? :resume : :start) )
          profile_klass.class_variable_set('@@profiling', true)
        end
        after  { RubyProf.pause  }
      }

      profile_klass.bootstrap(:config => config, :redis_config => redis_options)

      server = Thin::Server.new('0.0.0.0', FLAPJACK_PORT,
        profile_klass, :signals => false)

      server.start

      EM.defer(block, proc {
        result = RubyProf.stop
        server.stop!
        Fiber.new {
          profile_klass.cleanup
        }
        printer = RubyProf::MultiPrinter.new(result)
        printer.print(:path => output_dir, :profile => name)
        EM.stop
      })
    end

    empty_db(:redis => redis)
    redis.quit
  end

  ### utility methods

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

  def empty_db(options = {})
    redis = options[:redis]
    redis.flushdb
  end

  ## end utility methods

  desc "profile executive with rubyprof"
  task :executive do

    require 'flapjack/executive'
    require 'flapjack/data/event'

    FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'profile'
    config_env, redis_options = load_config
    profile_pikelet(Flapjack::Executive, 'executive', config_env['executive'],
      redis_options) {

      # this executes in a separate thread, so no Fibery stuff is allowed
      redis = Redis.new(redis_options.merge(:driver => 'ruby'))

      REPETITIONS.times do |n|
        Flapjack::Data::Event.add({'entity'  => 'clientx-app-01',
                                   'check'   => 'ping',
                                   'type'    => 'service',
                                   'state'   => (n ? 'ok' : 'critical'),
                                   'summary' => 'testing'},
                                  :redis => redis)
      end
      redis.quit
    }
  end

  # NB: you'll need to access a real jabber server for this; if external events
  # come in from that then runs will not be comparable
  desc "profile jabber gateway with rubyprof"
  task :jabber do

    require 'flapjack/jabber'
    require 'flapjack/data/alert'
    require 'flapjack/data/contact'
    require 'flapjack/data/event'
    require 'flapjack/data/notification'

    FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'profile'
    config_env, redis_options = load_config
    profile_pikelet(Flapjack::Gateways::Jabber, 'jabber', config_env['jabber_gateway'],
      redis_options) {

        # this executes in a separate thread, so no Fibery stuff is allowed
        redis = Redis.new(redis_options.merge(:driver => 'ruby'))

        event = Flapjack::Data::Event.new('type'    => 'service',
                                          'state'   => 'critical',
                                          'summary' => '100% packet loss',
                                          'entity'  => 'clientx-app-01',
                                          'check'   => 'ping')
        notification = Flapjack::Data::Notification.for_event(event)

        contact = Flapjack::Data::Contact.find_by_id('1000', :redis => redis)

        REPETITIONS.times do |n|
          notification.messages(:contacts => [contact]).each do |msg|
            contents = msg.contents
            contents['event_count'] = n
            Flapjack::Data::Alert.add(config_env['jabber_gateway']['queue'],
              contents)
          end
        end

        redis.quit
    }
  end

  # NB: you'll need an external email server set up for this (whether it's
  # mailtrap or a real server)
  desc "profile email notifier with rubyprof"
  task :email do

    require 'flapjack/email'
    require 'flapjack/data/alert'
    require 'flapjack/data/contact'
    require 'flapjack/data/event'
    require 'flapjack/data/notification'

    FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'profile'
    config_env, redis_options = load_config
    profile_pikelet(Flapjack::Gateways::Email, 'jabber', config_env['jabber_gateway'],
      redis_options) {

        # this executes in a separate thread, so no Fibery stuff is allowed
        redis = Redis.new(redis_options.merge(:driver => 'ruby'))

        event = Flapjack::Data::Event.new('type'    => 'service',
                                          'state'   => 'critical',
                                          'summary' => '100% packet loss',
                                          'entity'  => 'clientx-app-01',
                                          'check'   => 'ping')
        notification = Flapjack::Data::Notification.for_event(event)

        contact = Flapjack::Data::Contact.find_by_id('1000', :redis => redis)

        REPETITIONS.times do |n|
          notification.messages(:contacts => [contact]).each do |msg|
            contents = msg.contents
            contents['event_count'] = n
            Flapjack::Data::Alert.add(config_env['email_gateway']['queue'],
              contents)
          end
        end

        redis.quit
    }
  end

  # Of course, if external requests come to this server then different runs will
  # not be comparable
  desc "profile web server with rubyprof"
  task :web do

    require 'net/http'
    require 'uri'

    require 'flapjack/web'

    FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'profile'
    config_env, redis_options = load_config
    profile_thin(Flapjack::Web, 'web', config_env['web'], redis_options) {
      uri = URI.parse("http://127.0.0.1:#{FLAPJACK_PORT}/")

      http = Net::HTTP.new(uri.host, uri.port)

      REPETITIONS.times do |n|
        request = Net::HTTP::Get.new(uri.request_uri)
        response = http.request(request)
      end
    }
  end

end