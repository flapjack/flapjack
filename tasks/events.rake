require 'redis'

namespace :events do

  # FIXME: add arguments, make more flexible
  desc "send events to trigger some notifications"
  task :test_notification do

    # add lib to the default include path
    unless $:.include?(File.dirname(__FILE__) + '/../lib/')
      $: << File.dirname(__FILE__) + '/../lib'
    end

    require 'flapjack/configuration'
    require 'flapjack/data/event'

    FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'development'
    config_file = File.join('etc', 'flapjack_config.yaml')
    config = Flapjack::Configuration.new
    config.load(config_file)
    @config = config.all
    @redis_config = config.for_redis

    if @config.nil? || @config.empty?
      puts "No config data for environment '#{FLAPJACK_ENV}' found in '#{config_file}'"
      exit(false)
    end

    redis = Redis.new(@redis_config)

    Flapjack::Data::Event.add({'entity'  => 'clientx-app-01',
                               'check'   => 'ping',
                               'type'    => 'service',
                               'state'   => 'ok',
                               'summary' => 'testing'}, :redis => redis)

    sleep(8)

    Flapjack::Data::Event.add({'entity'  => 'clientx-app-01',
                               'check'   => 'ping',
                               'type'    => 'service',
                               'state'   => 'critical',
                               'summary' => 'testing'}, :redis => redis)

    sleep(8)

    Flapjack::Data::Event.add({'entity'  => 'clientx-app-01',
                               'check'   => 'ping',
                               'type'    => 'service',
                               'state'   => 'ok',
                               'summary' => 'testing'}, :redis => redis)

  end

end