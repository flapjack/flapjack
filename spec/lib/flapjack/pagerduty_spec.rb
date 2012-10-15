require 'spec_helper'

require 'yajl/json_gem'

require 'flapjack/pagerduty'

describe Flapjack::Pagerduty, :redis => true do

  let(:config) { {'queue'    => 'pagerduty_notifications'} }

  let(:time)   { Time.new }

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

  # Testing the private PagerDuty methods separately, it's simpler. May be
  # an argument for splitting some of them to another module, accessed by this
  # class, in which case it makes more sense for the methods to be public.

  # NB: needs to run in synchrony block to catch the evented HTTP requests
  it "looks for acknowledgements via the PagerDuty API" do
    EM.synchrony do
      fp = Flapjack::Pagerduty.new
      fp.bootstrap(:config => config)

      check = 'PING'
      Time.should_receive(:now).and_return(time)
      since = (time.utc - (60*60*24*7)).iso8601 # the last week
      unt   = (time.utc + (60*60*24)).iso8601   # 1 day in the future

      response = {"incidents" =>
        [{"incident_number" => 12,
          "status" => "acknowledged",
          "last_status_change_by" => {"id"=>"ABCDEFG", "name"=>"John Smith",
                                      "email"=>"johns@example.com",
                                      "html_url"=>"http://flpjck.pagerduty.com/users/ABCDEFG"}
         }
        ],
        "limit"=>100,
        "offset"=>0,
        "total"=>1}

      stub_request(:get, "https://flpjck.pagerduty.com/api/v1/incidents?" +
        "fields=incident_number,status,last_status_change_by&incident_key=#{check}&" +
        "since=#{since}&status=acknowledged&until=#{unt}").
         with(:headers => {'Authorization'=>['flapjack', 'password123']}).
         to_return(:status => 200, :body => response.to_json, :headers => {})

      result = fp.send(:pagerduty_acknowledged?, 'subdomain' => 'flpjck', 'username' => 'flapjack',
        'password' => 'password123', 'check' => check)

      result.should be_a(Hash)
      result.should have_key(:pg_acknowledged_by)
      result[:pg_acknowledged_by].should be_a(Hash)
      result[:pg_acknowledged_by].should have_key('id')
      result[:pg_acknowledged_by]['id'].should == 'ABCDEFG'
      EM.stop
    end
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
