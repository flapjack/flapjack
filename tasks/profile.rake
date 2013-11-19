namespace :profile do

  # # FIXME Needs to be ported across to the new threading structures

  require 'fileutils'
  require 'flapjack/configuration'

  FLAPJACK_ROOT   = File.join(File.dirname(__FILE__), '..')
  FLAPJACK_CONFIG = File.join(FLAPJACK_ROOT, 'etc', 'flapjack_config.yaml')

  FLAPJACK_PROFILER = ENV['FLAPJACK_PROFILER'] || 'rubyprof'
  port = ENV['FLAPJACK_PROFILER'].to_i
  FLAPJACK_PORT = ((port > 1024) && (port <= 65535)) ? port : 8075

  REPETITIONS     = 10

  require 'ruby-prof'

  require 'flapjack/redis_proxy'
  require 'flapjack/pikelet'

  def profile_pikelet(type, config, redis_options)
    Flapjack::RedisProxy.config = redis_options
    check_db_empty(:redis => redis_options)
    setup_baseline_data

    @monitor = Monitor.new
    @cond    = @monitor.new_cond
    @status  = 'uninitialized'

    RubyProf.start

    Thread.new do
      @monitor.synchronize do
        @cond.wait_until { @status == 'initialized' }
        yield
        @status = 'finished'
        @cond.signal
      end
      # redis connections are thread-local, so quitting at the end of each thread
      Flapjack.redis.quit
    end

    pikelets = Flapjack::Pikelet.create(type, nil, :config => config)

    @monitor.synchronize do
      pikelets.each do |pik|
        pik.start
      end

      # give webrick some time to start
      sleep(3) if 'web'.eql?(type)

      @status = 'initialized'
      @cond.signal

      @cond.wait_until { @status == 'finished' }
    end

    pikelets.each do |pik|
      pik.stop
    end
    result = RubyProf.stop

    Flapjack.redis.flushdb
    Flapjack.redis.quit

    # result.eliminate_methods!([/Mutex/])
    printer = RubyProf::MultiPrinter.new(result)
    output_dir = File.join('tmp', 'profiles')
    FileUtils.mkdir_p(output_dir)
    printer.print(:path => output_dir, :profile => type)
  end

  # ### utility methods

  def load_config
    config = Flapjack::Configuration.new
    config.load(FLAPJACK_CONFIG)
    config_env = config.all
    if config_env.nil? || config_env.empty?
      puts "No config data for environment '#{FLAPJACK_ENV}' " +
        "found in '#{FLAPJACK_CONFIG}'"
      exit(false)
    end

    return config_env, config.for_redis
  end

  def check_db_empty(options = {})
    # DBSIZE can return > 0 with expired keys -- but that's fine, we only
    # want to run against an explicitly empty DB. If this fails against the
    # intended Redis DB, the user can FLUSHDB it manually
    db_size = Flapjack.redis.dbsize.to_i
    if db_size > 0
      db = options[:redis]['db']
      puts "The Redis database has a non-zero DBSIZE (#{db_size}) -- "
           "profiling will destroy data. Use 'SELECT #{db}; FLUSHDB' in " +
           'redis-cli if you want to profile using this database.'
      puts "[redis options] #{options[:redis].inspect}\nExiting..."
      exit(false)
    end
  end

  # # this adds a default entity and contact, so that the profiling methods
  # # will actually trigger enough code to be useful
  def setup_baseline_data(options = {})
    entity = {"id" => "2000",
              "name" => "clientx-app-01",
              "contacts" => ["1000"]}

    Flapjack::Data::Entity.add(entity)

    contact = {'id' => '1000',
               'first_name' => 'John',
               'last_name' => 'Smith',
               'email' => 'jsmith@example.com',
               'media' => {
                 'email' => 'jsmith@example.com'
               }}

    Flapjack::Data::Contact.add(contact)

    # entity = Flapjack::Data::Entity.new(:id => "2000", :name => "clientx-app-01")
    # entity.save

    # contact = Flapjack::Data::Contact.new(:id => '1000',
    #   :first_name => 'John', :last_name => 'Smith',
    #   :email => 'jsmith@example.com')
    # contact.save

    # medium = Flapjack::Data::medium.new(:type => 'email', :address => 'jsmith@example.com')
    # medium.save

    # contact.media << medium
    # entity.contacts << contact
  end

  def message_contents
    contact = Flapjack::Data::Contact.find_by_id('1000')

    {'notification_type'   => 'problem',
     'contact_first_name'  => contact.first_name,
     'contact_last_name'   => contact.last_name,
     'address'             => contact.email,
     'state'               => 'critical',
     'state_duration'      => 23,
     'summary'             => '',
     'last_state'          => 'ok',
     'last_summary'        => 'profiling',
     'details'             => 'Profiling!',
     'time'                => Time.now.to_i,
     'event_id'            => 'clientx-app-01:ping'}
  end

  def profile_message_gateway(type, queue)
    config_env, redis_options = load_config
    profile_pikelet(type, config_env['gateways'][type], redis_options) do
      begin
        msg_contents = message_contents

        REPETITIONS.times do |n|
          msg_contents['event_count'] = n
          Flapjack.redis.lpush(queue, Oj.dump(msg_contents))
          Flapjack.redis.lpush("#{queue}_actions", "+")
        end
      rescue => e
        puts e.message
        puts e.backtrace.join("\n")
      end

    end
  end

  # ## end utility methods

  desc "profile processor with rubyprof"
  task :processor do
    require 'flapjack/processor'
    require 'flapjack/data/event'

    FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'profile'
    config_env, redis_options = load_config
    profile_generic('processor', config_env['processor'], redis_options) do
      REPETITIONS.times do |n|
        Flapjack::Data::Event.push('events', {'entity'  => 'clientx-app-01',
                                              'check'   => 'ping',
                                              'type'    => 'service',
                                              'state'   => (n ? 'ok' : 'critical'),
                                              'summary' => 'testing'})
      end
    end
  end

  # # NB: you'll need to access a real jabber server for this; if external events
  # # come in from that then runs will not be comparable
  desc "profile jabber gateway with rubyprof"
  task :jabber do
    require 'flapjack/data/contact'
    require 'flapjack/data/event'
    require 'flapjack/data/notification'

    require 'flapjack/gateways/jabber'

    FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'profile'
    profile_message_gateway('jabber', config_env['gateways']['jabber']['queue'])
  end

  # NB: you'll need an external email server set up for this (whether it's
  # mailtrap or a real server)
  desc "profile email notifier with rubyprof"
  task :email do
    require 'flapjack/data/contact'
    require 'flapjack/data/event'
    require 'flapjack/data/notification'

    require 'flapjack/gateways/email'

    FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'profile'
    profile_message_gateway('email', config_env['gateways']['email']['queue'])
  end

  # Of course, if external requests come to this server then different runs will
  # not be comparable
  desc "profile web server with rubyprof"
  task :web do
    require 'net/http'

    require 'flapjack/gateways/web'

    FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'profile'
    config_env, redis_options = load_config
    profile_pikelet('web', config_env['gateways']['web'], redis_options) {
      uri = URI.parse("http://127.0.0.1:#{FLAPJACK_PORT}/")
      REPETITIONS.times do |n|
        begin
          response = Net::HTTP.get(uri)
        rescue => e
          puts e.message
          puts e.backtrace.join("\n")
        end
      end
    }
  end

end