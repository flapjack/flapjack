
require 'redis'
require 'yaml'
require 'yajl'

namespace :events do

  # FIXME: add arguments, make more flexible
  desc "send events to trigger some notifications"
  task :test_notification do

    # config file reading stuff ...
    # FIXME: move this into somewhere reusable
    FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'development'
    config_file = File.join('etc', 'flapjack_config.yaml')
    if File.file?(config_file)
      config = YAML::load(File.open(config_file))
    else
      puts "Could not find 'etc/flapjack_config.yaml'"
      exit(false)
    end
    config_env = config[FLAPJACK_ENV]
    @redis_host = config_env['redis']['host'] || 'localhost'
    @redis_port = config_env['redis']['port'] || '6379'
    @redis_path = config_env['redis']['path'] || nil
    @redis_db   = config_env['redis']['db']   || 0

    if config_env.nil? || config_env.empty?
        puts "No config data for environment '#{FLAPJACK_ENV}'"
          exit(false)
    end

    # add lib to the default include path
    unless $:.include?(File.dirname(__FILE__) + '/../lib/')
      $: << File.dirname(__FILE__) + '/../lib'
    end

    def get_redis_connection
      if @redis_path
        redis = Redis.new(:db => @redis_db, :path => @redis_path)
      else
        redis = Redis.new(:db => @redis_db, :host => @redis_host, :port => @redis_port)
      end
      redis
    end

    # creates an event object and adds it to the events list in redis
    #   'entity'    => entity,
    #   'check'     => check,
    #   'type'      => 'service',
    #   'state'     => state,
    #   'summary'   => check_output,
    #   'time'      => timestamp,
    def create_event(event)
      redis = get_redis_connection
      evt = Yajl::Encoder.encode(event)
      puts "sending #{evt}"
      redis.rpush('events', evt)
    end

    create_event( 'entity'  => 'clientx-app-01',
                  'check'   => 'ping',
                  'type'    => 'service',
                  'state'   => 'ok',
                  'summary' => 'testing' )

    sleep(8)

    create_event( 'entity'  => 'clientx-app-01',
                  'check'   => 'ping',
                  'type'    => 'service',
                  'state'   => 'critical',
                  'summary' => 'testing' )

    sleep(8)

    create_event( 'entity'  => 'clientx-app-01',
                  'check'   => 'ping',
                  'type'    => 'service',
                  'state'   => 'ok',
                  'summary' => 'testing' )

  end

end