require 'spec_helper'

require 'flapjack/gateways/pagerduty'

describe Flapjack::Gateways::Pagerduty, :logger => true do

  let(:config) { {'queue'    => 'pagerduty_notifications'} }

  let(:now)   { Time.now }

  let(:redis) {  double(Redis) }

  let(:lock)  { double(Monitor) }

  before(:each) do
    allow(Flapjack).to receive(:redis).and_return(redis)
  end

  context 'notifications' do

    let(:message) { {'notification_type'  => 'problem',
                     'contact_first_name' => 'John',
                     'contact_last_name' => 'Smith',
                     'address' => 'pdservicekey',
                     'state' => 'critical',
                     'state_duration' => 23,
                     'summary' => '',
                     'last_state' => 'OK',
                     'last_summary' => 'TEST',
                     'details' => 'Testing',
                     'time' => now.to_i,
                     'event_id' => 'app-02:ping'}
                  }

    # TODO use separate threads in the test instead?
    it "starts and is stopped by an exception" do
      expect(Kernel).to receive(:sleep).with(10)

      expect(Flapjack::Data::Message).to receive(:foreach_on_queue).
        with('pagerduty_notifications').and_yield(message)

      expect(Flapjack::Data::Message).to receive(:wait_for_queue).
        with('pagerduty_notifications').and_raise(Flapjack::PikeletStop)

      expect(lock).to receive(:synchronize).and_yield

      fpn = Flapjack::Gateways::Pagerduty::Notifier.new(:lock => lock,
        :config => config, :logger => @logger)
      expect(fpn).to receive(:handle_message).with(message)
      expect(fpn).to receive(:test_pagerduty_connection).twice.and_return(false, true)
      expect { fpn.start }.to raise_error(Flapjack::PikeletStop)
    end

    it "tests the pagerduty connection" do
      fpn = Flapjack::Gateways::Pagerduty::Notifier.new(:config => config, :logger => @logger)

      req = stub_request(:post, "https://events.pagerduty.com/generic/2010-04-15/create_event.json").
         with(:body => {'service_key'  => '11111111111111111111111111111111',
                        'incident_key' => 'Flapjack is running a NOOP',
                        'event_type'   => 'nop',
                        'description'  => 'I love APIs with noops.'}.to_json).
         to_return(:status => 200, :body => {'status' => 'success'}.to_json)

      fpn.send(:test_pagerduty_connection)
      expect(req).to have_been_requested
    end

    it "handles notifications received via Redis" do
      fpn = Flapjack::Gateways::Pagerduty::Notifier.new(:config => config, :logger => @logger)

      req = stub_request(:post, "https://events.pagerduty.com/generic/2010-04-15/create_event.json").
         with(:body => {'service_key'  => 'pdservicekey',
                        'incident_key' => 'app-02:ping',
                        'event_type'   => 'trigger',
                        'description'  => 'Problem: "ping" on app-02 is Critical'}.to_json).
         to_return(:status => 200, :body => {'status' => 'success'}.to_json)

      fpn.send(:handle_message, message)
      expect(req).to have_been_requested
    end

  end

  context 'acknowledgements' do

    let(:entity_check) { double(Flapjack::Data::EntityCheck) }

    let(:status_change) { {'id'        => 'ABCDEFG',
                           'name'      => 'John Smith',
                           'email'     => 'johns@example.com',
                           'html_url'  => 'http://flpjck.pagerduty.com/users/ABCDEFG'}
                        }

    # TODO use separate threads in the test instead?
    it "doesn't look for acknowledgements if this search is already running" do
      expect(redis).to receive(:del).with('sem_pagerduty_acks_running')

      expect(redis).to receive(:setnx).with('sem_pagerduty_acks_running', 'true').and_return(0)

      expect(Kernel).to receive(:sleep).with(10).and_raise(Flapjack::PikeletStop.new)

      expect(lock).to receive(:synchronize).and_yield

      fpa = Flapjack::Gateways::Pagerduty::AckFinder.new(:lock => lock,
        :config => config, :logger => @logger)
      expect { fpa.start }.to raise_error(Flapjack::PikeletStop)
    end

    # TODO use separate threads in the test instead?
    it "looks for and creates acknowledgements if the search is not already running" do
      expect(redis).to receive(:del).with('sem_pagerduty_acks_running').twice

      expect(redis).to receive(:setnx).with('sem_pagerduty_acks_running', 'true').and_return(1)
      expect(redis).to receive(:expire).with('sem_pagerduty_acks_running', 300)

      contact = double(Flapjack::Data::Contact)
      expect(contact).to receive(:pagerduty_credentials).and_return({
        'service_key' => '12345678',
        'subdomain"'  => 'flpjck',
        'username'    => 'flapjack',
        'password'    => 'password123'
      })

      expect(entity_check).to receive(:contacts).and_return([contact])
      expect(entity_check).to receive(:check).and_return('PING')
      expect(entity_check).to receive(:entity_name).and_return('foo-app-01.bar.net')

      expect(Flapjack::Data::EntityCheck).to receive(:find_all_failing_unacknowledged).
        and_return(['PING:foo-app-01.bar.net'])

      expect(Flapjack::Data::EntityCheck).to receive(:for_event_id).
        with('PING:foo-app-01.bar.net').and_return(entity_check)

      expect(Flapjack::Data::Event).to receive(:create_acknowledgement).with('events',
        'foo-app-01.bar.net', 'PING',
        :summary => 'Acknowledged on PagerDuty by John Smith',
        :duration => 14400)

      expect(Kernel).to receive(:sleep).with(10).and_raise(Flapjack::PikeletStop.new)

      response = {:pg_acknowledged_by => status_change}

      expect(lock).to receive(:synchronize).and_yield

      fpa = Flapjack::Gateways::Pagerduty::AckFinder.new(:lock => lock,
        :config => config, :logger => @logger)
      expect(fpa).to receive(:pagerduty_acknowledged?).and_return(response)
      expect { fpa.start }.to raise_error(Flapjack::PikeletStop)
    end

    # testing separately and stubbing above
    it "looks for acknowledgements via the PagerDuty API" do
      check = 'PING'
      since = (now.utc - (60*60*24*7)).iso8601 # the last week
      unt   = (now.utc + (60*60*24)).iso8601   # 1 day in the future

      response = {"incidents" =>
        [{"incident_number" => 12,
          "status" => "acknowledged",
          "last_status_change_by" => status_change}],
        "limit"=>100,
        "offset"=>0,
        "total"=>1}

      req = stub_request(:get, "https://flapjack:password123@flpjck.pagerduty.com/api/v1/incidents").
        with(:query => {:fields => 'incident_number,status,last_status_change_by',
                        :incident_key => check, :since => since, :until => unt,
                        :status => 'acknowledged'}).
        to_return(:status => 200, :body => response.to_json, :headers => {})

      expect(redis).to receive(:del).with('sem_pagerduty_acks_running')

      fpa = Flapjack::Gateways::Pagerduty::AckFinder.new(:config => config, :logger => @logger)

      result = fpa.send(:pagerduty_acknowledged?, 'subdomain' => 'flpjck',
        'username' => 'flapjack', 'password' => 'password123', 'check' => check)

      expect(result).to be_a(Hash)
      expect(result).to have_key(:pg_acknowledged_by)
      expect(result[:pg_acknowledged_by]).to be_a(Hash)
      expect(result[:pg_acknowledged_by]).to have_key('id')
      expect(result[:pg_acknowledged_by]['id']).to eq('ABCDEFG')

      expect(req).to have_been_requested
    end

  end

end
