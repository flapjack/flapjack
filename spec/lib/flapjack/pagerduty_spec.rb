require 'spec_helper'
require 'flapjack/pagerduty'

describe Flapjack::Pagerduty, :redis => true do

  let(:config) { {'queue'    => 'pagerduty_notifications'} }

  it "prompts the blocking redis connection to quit" do
    redis = mock('redis')
    redis.should_receive(:rpush).with(nil, %q{{"notification_type":"shutdown"}})

    pagerduty = Flapjack::Pagerduty.new
    pagerduty.bootstrap(:redis => @redis)
    pagerduty.add_shutdown_event(:redis => redis)
  end

  it "runs a blocking loop listening for notifications" do
    timer = mock('timer')
    timer.should_receive(:cancel)
    EM::Synchrony.should_receive(:add_periodic_timer).with(10).and_return(timer)

    redis = mock('redis')
    redis.should_receive(:del).with('sem_pagerduty_acks_running')
    redis.should_receive(:empty!)

    fp = Flapjack::Pagerduty.new
    fp.bootstrap(:config => config)
    fp.should_receive(:build_redis_connection_pool).and_return(redis)

    fp.should_receive(:should_quit?).exactly(3).times.and_return(false, false, true)
    redis.should_receive(:blpop).twice.and_return(
      ["pagerduty_notifications", %q{{"notification_type":"problem","event_id":"main-example.com:ping","state":"critical","summary":"!!!"}}],
      ["pagerduty_notifications", %q{{"notification_type":"shutdown"}}]
    )

    # FIXME test these methods as well
    fp.should_receive(:test_pagerduty_connection).and_return(true)
    fp.should_receive(:send_pagerduty_event)

    fp.main
  end

end
