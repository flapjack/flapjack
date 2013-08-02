require 'spec_helper'

require 'flapjack/gateways/pagerduty'

describe Flapjack::Gateways::Pagerduty, :logger => true do

  let(:config) { {'queue'    => 'pagerduty_notifications'} }

  let(:time)   { Time.new }

  let(:redis) {  mock('redis') }

  # it "prompts the blocking redis connection to quit" do
  #   redis.should_receive(:rpush).with(config['queue'], %q{{"notification_type":"shutdown"}})
  #   ::Redis.should_receive(:new).and_return(redis)

  #   fp = Flapjack::Gateways::Pagerduty.new(:config => config, :logger => @logger)
  #   fp.stop
  # end

  # it "doesn't look for acknowledgements if this search is already running" do
  #   redis.should_receive(:get).with('sem_pagerduty_acks_running').and_return('true')
  #   ::Redis.should_receive(:new).and_return(redis)
  #   fp = Flapjack::Gateways::Pagerduty::AckFinder.new(:config => config, :logger => @logger)

  #   fp.should_not_receive(:find_pagerduty_acknowledgements)
  #   fp.find_pagerduty_acknowledgements_if_safe
  # end

  # it "looks for acknowledgements if the search is not already running" do
  #   redis.should_receive(:get).with('sem_pagerduty_acks_running').and_return(nil)
  #   redis.should_receive(:set).with('sem_pagerduty_acks_running', 'true')
  #   redis.should_receive(:expire).with('sem_pagerduty_acks_running', 300)

  #   redis.should_receive(:del).with('sem_pagerduty_acks_running')

  #   ::Redis.should_receive(:new).and_return(redis)
  #   fp = Flapjack::Gateways::Pagerduty.new(:config => config, :logger => @logger)

  #   fp.should_receive(:find_pagerduty_acknowledgements)
  #   fp.find_pagerduty_acknowledgements_if_safe
  # end

  # # Testing the private PagerDuty methods separately, it's simpler. May be
  # # an argument for splitting some of them to another module, accessed by this
  # # class, in which case it makes more sense for the methods to be public.

  # # NB: needs to run in synchrony block to catch the evented HTTP requests
  # it "looks for acknowledgements via the PagerDuty API" do
  #   check = 'PING'
  #   Time.should_receive(:now).and_return(time)
  #   since = (time.utc - (60*60*24*7)).iso8601 # the last week
  #   unt   = (time.utc + (60*60*24)).iso8601   # 1 day in the future

  #   response = {"incidents" =>
  #     [{"incident_number" => 12,
  #       "status" => "acknowledged",
  #       "last_status_change_by" => {"id"=>"ABCDEFG", "name"=>"John Smith",
  #                                   "email"=>"johns@example.com",
  #                                   "html_url"=>"http://flpjck.pagerduty.com/users/ABCDEFG"}
  #      }
  #     ],
  #     "limit"=>100,
  #     "offset"=>0,
  #     "total"=>1}

  #   stub_request(:get, "https://flpjck.pagerduty.com/api/v1/incidents?" +
  #     "fields=incident_number,status,last_status_change_by&incident_key=#{check}&" +
  #     "since=#{since}&status=acknowledged&until=#{unt}").
  #      with(:headers => {'Authorization'=>['flapjack', 'password123']}).
  #      to_return(:status => 200, :body => response.to_json, :headers => {})

  #   ::Redis.should_receive(:new).and_return(redis)
  #   fp = Flapjack::Gateways::Pagerduty.new(:config => config, :logger => @logger)

  #   result = fp.send(:pagerduty_acknowledged?, 'subdomain' => 'flpjck', 'username' => 'flapjack',
  #     'password' => 'password123', 'check' => check)

  #   result.should be_a(Hash)
  #   result.should have_key(:pg_acknowledged_by)
  #   result[:pg_acknowledged_by].should be_a(Hash)
  #   result[:pg_acknowledged_by].should have_key('id')
  #   result[:pg_acknowledged_by]['id'].should == 'ABCDEFG'
  # end

  # it "creates acknowledgements when pagerduty acknowledgements are found" do
  #   ::Redis.should_receive(:new).and_return(redis)

  #   fp = Flapjack::Gateways::Pagerduty.new(:config => config, :logger => @logger)

  #   contact = mock('contact')
  #   contact.should_receive(:pagerduty_credentials).and_return({
  #     'service_key' => '12345678',
  #     'subdomain"'  => 'flpjck',
  #     'username'    => 'flapjack',
  #     'password'    => 'password123'
  #   })

  #   entity_check = mock('entity_check')
  #   entity_check.should_receive(:check).and_return('PING')
  #   entity_check.should_receive(:contacts).and_return([contact])
  #   entity_check.should_receive(:entity_name).exactly(2).times.and_return('foo-app-01.bar.net')
  #   Flapjack::Data::Event.should_receive(:create_acknowledgement).with('foo-app-01.bar.net', 'PING',
  #     :summary => 'Acknowledged on PagerDuty', :redis => redis)

  #   Flapjack::Data::Global.should_receive(:unacknowledged_failing_checks).and_return([entity_check])

  #   fp.should_receive(:pagerduty_acknowledged?).and_return({})

  #   fp.send(:find_pagerduty_acknowledgements)
  # end

  # it "runs a blocking loop listening for notifications" do
  #   redis.should_receive(:del).with('sem_pagerduty_acks_running')

  #   ::Redis.should_receive(:new).and_return(redis)
  #   fp = Flapjack::Gateways::Pagerduty.new(:config => config, :logger => @logger)

  #   blpop_count = 0

  #   redis.should_receive(:blpop).twice {
  #     blpop_count += 1
  #     if blpop_count == 1
  #       ["pagerduty_notifications", %q{{"notification_type":"problem","event_id":"main-example.com:ping","state":"critical","summary":"!!!"}}]
  #     else
  #       fp.instance_variable_set('@should_quit', true)
  #       ["pagerduty_notifications", %q{{"notification_type":"shutdown"}}]
  #     end
  #   }

  #   fp.should_receive(:test_pagerduty_connection).and_return(true)
  #   fp.should_receive(:send_pagerduty_event)

  #   fp.start
  # end

  # it "tests the pagerduty connection" do
  #   evt = { "service_key"  => "11111111111111111111111111111111",
  #           "incident_key" => "Flapjack is running a NOOP",
  #           "event_type"   => "nop",
  #           "description"  => "I love APIs with noops." }
  #   body = evt.to_json

  #   stub_request(:post, "https://events.pagerduty.com/generic/2010-04-15/create_event.json").
  #     with(:body => body).to_return(:status => 200, :body => '{"status":"success"}', :headers => {})

  #   ::Redis.should_receive(:new).and_return(redis)
  #   fp = Flapjack::Gateways::Pagerduty.new(:config => config, :logger => @logger)

  #   ret = fp.send(:test_pagerduty_connection)
  #   ret.should be_true
  # end

  # it "sends an event to pagerduty" do
  #   evt = {"service_key"  => "abcdefg",
  #          "incident_key" => "Flapjack test",
  #          "event_type"   => "nop",
  #          "description"  => "Not really sent anyway"}
  #   body = evt.to_json

  #   stub_request(:post, "https://events.pagerduty.com/generic/2010-04-15/create_event.json").
  #     with(:body => body).to_return(:status => 200, :body => "", :headers => {})

  #   ::Redis.should_receive(:new).and_return(redis)
  #   fp = Flapjack::Gateways::Pagerduty.new(:config => config, :logger => @logger)

  #   ret = fp.send(:send_pagerduty_event, evt)
  #   ret.should_not be_nil
  #   ret.should == [200, nil]
  # end

end
