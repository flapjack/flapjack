
namespace :events do 

  # FIXME: add arguments, make more flexible
  desc "send events to trigger some notifications"
  task :test_notification do
  
    FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'development'
    require 'bundler'
    Bundler.require(:default, FLAPJACK_ENV.to_sym)
  
    # creates an event object and adds it to the events list in redis
    #   'entity'    => entity,
    #   'check'     => check,
    #   'type'      => 'service',
    #   'state'     => state,
    #   'summary'   => check_output,
    #   'time'      => timestamp,
    def create_event(event)
      redis = ::Redis.new(:driver => :ruby)
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
                  'state'   => 'failed',
                  'summary' => 'testing' )

    sleep(8)

    create_event( 'entity'  => 'clientx-app-01',
                  'check'   => 'ping',
                  'type'    => 'service',
                  'state'   => 'ok',
                  'summary' => 'testing' )

  end

end