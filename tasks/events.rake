require 'redis'

namespace :events do

  # add lib to the default include path
  unless $:.include?(File.dirname(__FILE__) + '/../lib/')
    $: << File.dirname(__FILE__) + '/../lib'
  end

  require 'flapjack'
  require 'flapjack/configuration'
  require 'flapjack/data/event'

  # FIXME: add arguments, make more flexible
  desc "send events to trigger some notifications"
  task :test_notification do

    FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'development'
    config_file = File.join('etc', 'flapjack_config.toml')

    config = Flapjack::Configuration.new
    config.load( config_file )

    @config_env = config.all
    @redis_config = config.for_redis

    if @config_env.nil? || @config_env.empty?
      puts "No config data found in '#{config_file}'"
      exit(false)
    end

    Flapjack.redis = Redis.new(@redis_config)

    Flapjack::Data::Event.add({'entity'  => 'clientx-app-01',
                               'check'   => 'ping',
                               'type'    => 'service',
                               'state'   => 'ok',
                               'summary' => 'testing'})

    sleep(8)

    Flapjack::Data::Event.add({'entity'  => 'clientx-app-01',
                               'check'   => 'ping',
                               'type'    => 'service',
                               'state'   => 'critical',
                               'summary' => 'testing'})

    sleep(8)

    Flapjack::Data::Event.add({'entity'  => 'clientx-app-01',
                               'check'   => 'ping',
                               'type'    => 'service',
                               'state'   => 'ok',
                               'summary' => 'testing'})

  end


end
