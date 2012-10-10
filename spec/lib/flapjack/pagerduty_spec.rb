require 'spec_helper'
require 'flapjack/pagerduty'

describe Flapjack::Pagerduty, :redis => true do

  let(:config) { {'queue'    => 'pagerduty_notifications'} }

  it "prompts the blocking redis connection to quit" do
    redis = mock('redis')
    redis.should_receive(:rpush).with(nil, %q{{"notification_type":"shutdown"}})

    pagerduty = Flapjack::Pagerduty.new
    pagerduty.bootstrap
    pagerduty.add_shutdown_event(:redis => redis)
  end

  it "doesn't look for acknowledgements if this search is already running" do
    @redis.set(Flapjack::Pagerduty::SEM_PAGERDUTY_ACKS_RUNNING, 'true')

    fp = Flapjack::Pagerduty.new
    fp.bootstrap(:config => config)
    fp.instance_variable_set("@redis_timer", @redis)

    fp.should_not_receive(:find_pagerduty_acknowledgements)
    fp.find_pagerduty_acknowledgements_if_safe
  end

  it "looks for acknowledgements if the search is not already running" do
    fp = Flapjack::Pagerduty.new
    fp.bootstrap(:config => config)
    fp.instance_variable_set("@redis_timer", @redis)

    fp.should_receive(:find_pagerduty_acknowledgements)
    fp.find_pagerduty_acknowledgements_if_safe
  end

  # NB: will need to run in EM block to catch the evented HTTP requests
  it "looks for acknowledgements via the PagerDuty API" do
    pending
    EM.run_block {
    }
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
