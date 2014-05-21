require 'spec_helper'

require 'flapjack/gateways/pagerduty'

describe Flapjack::Gateways::Pagerduty, :logger => true do

  let(:config) { {'queue'    => 'pagerduty_notifications'} }

  let(:time)   { Time.new }

  let(:redis) {  double('redis') }

  it "prompts the blocking redis connection to quit" do
    shutdown_redis = double('shutdown_redis')
    expect(shutdown_redis).to receive(:rpush).with(config['queue'], %q{{"notification_type":"shutdown"}})
    expect(EM::Hiredis).to receive(:connect).and_return(shutdown_redis)

    expect(Flapjack::RedisPool).to receive(:new).and_return(redis)
    fp = Flapjack::Gateways::Pagerduty.new(:config => config, :logger => @logger)
    fp.stop
  end

  it "doesn't look for acknowledgements if this search is already running" do
    expect(redis).to receive(:get).with('sem_pagerduty_acks_running').and_return('true')
    expect(Flapjack::RedisPool).to receive(:new).and_return(redis)
    fp = Flapjack::Gateways::Pagerduty.new(:config => config, :logger => @logger)

    expect(fp).not_to receive(:find_pagerduty_acknowledgements)
    fp.find_pagerduty_acknowledgements_if_safe
  end

  it "looks for acknowledgements if the search is not already running" do
    expect(redis).to receive(:get).with('sem_pagerduty_acks_running').and_return(nil)
    expect(redis).to receive(:set).with('sem_pagerduty_acks_running', 'true')
    expect(redis).to receive(:expire).with('sem_pagerduty_acks_running', 300)

    expect(redis).to receive(:del).with('sem_pagerduty_acks_running')

    expect(Flapjack::RedisPool).to receive(:new).and_return(redis)
    fp = Flapjack::Gateways::Pagerduty.new(:config => config, :logger => @logger)

    expect(fp).to receive(:find_pagerduty_acknowledgements)
    fp.find_pagerduty_acknowledgements_if_safe
  end

  # Testing the private PagerDuty methods separately, it's simpler. May be
  # an argument for splitting some of them to another module, accessed by this
  # class, in which case it makes more sense for the methods to be public.

  # NB: needs to run in synchrony block to catch the evented HTTP requests
  it "looks for acknowledgements via the PagerDuty API" do
    check = 'PING'
    expect(Time).to receive(:now).and_return(time)
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

    expect(Flapjack::RedisPool).to receive(:new).and_return(redis)
    fp = Flapjack::Gateways::Pagerduty.new(:config => config, :logger => @logger)


    EM.synchrony do
      result = fp.send(:pagerduty_acknowledged?, 'subdomain' => 'flpjck', 'username' => 'flapjack',
        'password' => 'password123', 'check' => check)

      expect(result).to be_a(Hash)
      expect(result).to have_key(:pg_acknowledged_by)
      expect(result[:pg_acknowledged_by]).to be_a(Hash)
      expect(result[:pg_acknowledged_by]).to have_key('id')
      expect(result[:pg_acknowledged_by]['id']).to eq('ABCDEFG')
      EM.stop
    end

  end

  it "creates acknowledgements when pagerduty acknowledgements are found" do
    expect(Flapjack::RedisPool).to receive(:new).and_return(redis)
    fp = Flapjack::Gateways::Pagerduty.new(:config => config, :logger => @logger)

    contact = double('contact')
    expect(contact).to receive(:pagerduty_credentials).and_return({
      'service_key' => '12345678',
      'subdomain"'  => 'flpjck',
      'username'    => 'flapjack',
      'password'    => 'password123'
    })

    entity_check = double('entity_check')
    expect(entity_check).to receive(:check).and_return('PING')
    expect(entity_check).to receive(:contacts).and_return([contact])
    expect(entity_check).to receive(:entity_name).exactly(2).times.and_return('foo-app-01.bar.net')
    expect(Flapjack::Data::Event).to receive(:create_acknowledgement).with('foo-app-01.bar.net', 'PING',
      :summary => 'Acknowledged on PagerDuty', :duration => 14400, :redis => redis)

    expect(Flapjack::Data::EntityCheck).to receive(:unacknowledged_failing).and_return([entity_check])

    expect(fp).to receive(:pagerduty_acknowledged?).and_return({})

    fp.send(:find_pagerduty_acknowledgements)
  end

  it "runs a blocking loop listening for notifications" do
    timer = double('timer')
    expect(timer).to receive(:cancel)
    expect(EM::Synchrony).to receive(:add_periodic_timer).with(10).and_return(timer)

    expect(redis).to receive(:del).with('sem_pagerduty_acks_running')

    expect(Flapjack::RedisPool).to receive(:new).and_return(redis)
    fp = Flapjack::Gateways::Pagerduty.new(:config => config, :logger => @logger)

    blpop_count = 0

    expect(redis).to receive(:blpop).twice {
      blpop_count += 1
      if blpop_count == 1
        ["pagerduty_notifications", '{"notification_type":"problem","event_id":"main-example.com:ping",' +
          '"state":"critical","summary":"!!!","state_duration":120,"duration":30}']
      else
        fp.instance_variable_set('@should_quit', true)
        ["pagerduty_notifications", %q{{"notification_type":"shutdown"}}]
      end
    }

    expect(fp).to receive(:test_pagerduty_connection).and_return(true)
    expect(fp).to receive(:send_pagerduty_event)

    fp.start

    expect(@logger.errors).to be_empty
  end

  it "tests the pagerduty connection" do
    evt = { "service_key"  => "11111111111111111111111111111111",
            "incident_key" => "Flapjack is running a NOOP",
            "event_type"   => "nop",
            "description"  => "I love APIs with noops." }
    body = evt.to_json

    stub_request(:post, "https://events.pagerduty.com/generic/2010-04-15/create_event.json").
      with(:body => body).to_return(:status => 200, :body => '{"status":"success"}', :headers => {})

    expect(Flapjack::RedisPool).to receive(:new).and_return(redis)
    fp = Flapjack::Gateways::Pagerduty.new(:config => config, :logger => @logger)

    EM.synchrony do
      ret = fp.send(:test_pagerduty_connection)
      expect(ret).to be true
      EM.stop
    end
  end

  it "sends an event to pagerduty" do
    evt = {"service_key"  => "abcdefg",
           "incident_key" => "Flapjack test",
           "event_type"   => "nop",
           "description"  => "Not really sent anyway"}
    body = evt.to_json

    stub_request(:post, "https://events.pagerduty.com/generic/2010-04-15/create_event.json").
      with(:body => body).to_return(:status => 200, :body => "", :headers => {})

    expect(Flapjack::RedisPool).to receive(:new).and_return(redis)
    fp = Flapjack::Gateways::Pagerduty.new(:config => config, :logger => @logger)

    EM.synchrony do
      ret = fp.send(:send_pagerduty_event, evt)
      expect { ret }.not_to be_nil
      expect(ret).to eq([200, nil])
      EM.stop
    end
  end

  it "does not look for acknowledgements if all required credentials are not present" do
    creds = {'subdomain' => 'example',
             'username'  => 'sausage',
             'check'     => 'PING'}

    expect(Flapjack::RedisPool).to receive(:new).and_return(redis)
    fp = Flapjack::Gateways::Pagerduty.new(:config => config, :logger => @logger)
    EM.synchrony do
      result = fp.send(:pagerduty_acknowledged?, creds)

      expect(result).to be(nil)
      EM.stop
    end

  end

end
