require 'spec_helper'

require 'flapjack/gateways/pagerduty'

describe Flapjack::Gateways::Pagerduty, :logger => true do

  let(:config) { {'queue'    => 'pagerduty_notifications'} }

  let(:now)   { Time.new }

  let(:redis) { double(Redis) }
  let(:lock)  { double(Monitor) }

  let(:check) { double(Flapjack::Data::Check, :id => SecureRandom.uuid) }

  before(:each) do
    allow(Flapjack).to receive(:redis).and_return(redis)
  end

  context 'notifications' do

    let(:queue) { double(Flapjack::RecordQueue) }
    let(:alert) { double(Flapjack::Data::Alert) }

    it "starts and is stopped by an exception" do
      expect(Kernel).to receive(:sleep).with(10)

      expect(Flapjack::RecordQueue).to receive(:new).with('pagerduty_notifications',
        Flapjack::Data::Alert).and_return(queue)

      expect(lock).to receive(:synchronize).and_yield
      expect(queue).to receive(:foreach).and_yield(alert)
      expect(queue).to receive(:wait).and_raise(Flapjack::PikeletStop)

      expect(redis).to receive(:quit)

      fpn = Flapjack::Gateways::Pagerduty::Notifier.new(:lock => lock,
        :config => config, :logger => @logger)
      expect(fpn).to receive(:handle_alert).with(alert)
      expect(fpn).to receive(:test_pagerduty_connection).twice.and_return(false, true)
      expect { fpn.start }.to raise_error(Flapjack::PikeletStop)
    end

    it "tests the pagerduty connection" do
      fpn = Flapjack::Gateways::Pagerduty::Notifier.new(:config => config, :logger => @logger)

      req = stub_request(:post, "https://events.pagerduty.com/generic/2010-04-15/create_event.json").
         with(:body => Flapjack.dump_json(
                        'service_key'  => '11111111111111111111111111111111',
                        'incident_key' => 'Flapjack is running a NOOP',
                        'event_type'   => 'nop',
                        'description'  => 'I love APIs with noops.'
                       )).
         to_return(:status => 200, :body => Flapjack.dump_json('status' => 'success'))

      fpn.send(:test_pagerduty_connection)
      expect(req).to have_been_requested
    end

    it "handles notifications received via Redis" do
      fpn = Flapjack::Gateways::Pagerduty::Notifier.new(:config => config, :logger => @logger)

      req = stub_request(:post, "https://events.pagerduty.com/generic/2010-04-15/create_event.json").
        with(:body => Flapjack.dump_json(
                        'service_key'  => 'pdservicekey',
                        'incident_key' => 'app-02:ping',
                        'event_type'   => 'trigger',
                        'description'  => 'Problem: "app-02:ping" is Critical'
                       )).
         to_return(:status => 200, :body => Flapjack.dump_json('status' => 'success'))

      expect(check).to receive(:name).exactly(4).times.and_return('app-02:ping')

      expect(alert).to receive(:address).and_return('pdservicekey')
      expect(alert).to receive(:check).twice.and_return(check)
      expect(alert).to receive(:state).and_return('critical')
      expect(alert).to receive(:state_title_case).and_return('Critical')
      expect(alert).to receive(:summary).twice.and_return('')
      expect(alert).to receive(:type).twice.and_return('problem')
      expect(alert).to receive(:notification_type).and_return('problem')
      expect(alert).to receive(:type_sentence_case).and_return('Problem')

      fpn.send(:handle_alert, alert)
      expect(req).to have_been_requested
    end

  end

  context 'acknowledgements' do

    let(:status_change) { {'id'        => 'ABCDEFG',
                           'name'      => 'John Smith',
                           'email'     => 'johns@example.com',
                           'html_url'  => 'http://flpjck.pagerduty.com/users/ABCDEFG'}
                        }

    it "doesn't look for acknowledgements if this search is already running" do
      expect(redis).to receive(:del).with('sem_pagerduty_acks_running')

      expect(redis).to receive(:setnx).with('sem_pagerduty_acks_running', 'true').and_return(0)

      expect(Kernel).to receive(:sleep).with(10).and_raise(Flapjack::PikeletStop.new)

      expect(lock).to receive(:synchronize).and_yield

      fpa = Flapjack::Gateways::Pagerduty::AckFinder.new(:lock => lock,
        :config => config, :logger => @logger)
      expect { fpa.start }.to raise_error(Flapjack::PikeletStop)
    end

    it "looks for and creates acknowledgements if the search is not already running" do
      expect(redis).to receive(:del).with('sem_pagerduty_acks_running').twice

      expect(redis).to receive(:setnx).with('sem_pagerduty_acks_running', 'true').and_return(1)
      expect(redis).to receive(:expire).with('sem_pagerduty_acks_running', 300)

      expect(check).to receive(:name).exactly(3).times.and_return('app-02:ping')

      state = double(Flapjack::Data::State, :id => SecureRandom.uuid)
      states = double('states')

      expect(Flapjack::Data::Check).to receive(:associated_ids_for).
        with(:state).and_return(check.id => state.id)

      expect(Flapjack::Data::State).to receive(:intersect).
        with(:id => [state.id],
             :condition => ['critical', 'warning', 'unknown']).
        and_return(states)
      expect(states).to receive(:associated_ids_for).with(:check).
        and_return(state.id => check.id)

      checks = double('checks')
      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:id => [check.id]).and_return(checks)
      expect(checks).to receive(:select).and_yield(check).and_return([check])

      expect(check).to receive(:scheduled_maintenance_at).
        with(an_instance_of(Time)).and_return(nil)

      expect(check).to receive(:unscheduled_maintenance_at).
        with(an_instance_of(Time)).and_return(nil)

      expect(Flapjack::Data::Check).to receive(:pagerduty_credentials_for).
        and_return(check => [{
        'service_key' => '12345678',
        'subdomain"'  => 'flpjck',
        'username'    => 'flapjack',
        'password'    => 'password123'
      }])

      expect(Flapjack::Data::Event).to receive(:create_acknowledgements).with('events',
        [check],
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

      expect(Time).to receive(:now).and_return(now)

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
        to_return(:status => 200, :body => Flapjack.dump_json(response), :headers => {})

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

  it "does not look for acknowledgements if all required credentials are not present" # do
  #   creds = {'subdomain' => 'example',
  #            'username'  => 'sausage',
  #            'check'     => 'PING'}

  #   expect(Flapjack::RedisPool).to receive(:new).and_return(redis)
  #   fp = Flapjack::Gateways::Pagerduty.new(:config => config, :logger => @logger)
  #   EM.synchrony do
  #     result = fp.send(:pagerduty_acknowledged?, creds)

  #     expect(result).to be(nil)
  #     EM.stop
  #   end
  # end

end
