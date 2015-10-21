require 'spec_helper'

require 'flapjack/gateways/pager_duty'

describe Flapjack::Gateways::PagerDuty, :logger => true do

  let(:config) { {
    'queue'       => 'pagerduty_notifications',
    'credentials' => {'subdomain' => 'flpjck'}
  } }

  let(:now)   { Time.new }

  let(:redis) { double(Redis) }
  let(:lock)  { double(Monitor) }

  let(:check) { double(Flapjack::Data::Check, :id => SecureRandom.uuid,
    :name => 'app-02:ping') }

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

      fpn = Flapjack::Gateways::PagerDuty::Notifier.new(:lock => lock,
        :config => config)
      expect(fpn).to receive(:handle_alert).with(alert)
      expect(Flapjack::Gateways::PagerDuty).to receive(:test_pagerduty_connection).twice.and_return(false, true)
      expect { fpn.start }.to raise_error(Flapjack::PikeletStop)
    end

    it "tests the pagerduty connection" do
      req = stub_request(:post, "https://events.pagerduty.com/generic/2010-04-15/create_event.json").
         with(:body => Flapjack.dump_json(
                        'service_key'  => '11111111111111111111111111111111',
                        'incident_key' => 'Flapjack is running a NOOP',
                        'event_type'   => 'nop',
                        'description'  => 'I love APIs with noops.'
                       )).
         to_return(:status => 200, :body => Flapjack.dump_json('status' => 'success'))

      Flapjack::Gateways::PagerDuty.send(:test_pagerduty_connection)
      expect(req).to have_been_requested
    end

    it "handles notifications received via Redis" do
      fpn = Flapjack::Gateways::PagerDuty::Notifier.new(:config => config)

      req = stub_request(:post, "https://events.pagerduty.com/generic/2010-04-15/create_event.json").
        with(:body => Flapjack.dump_json(
                        'service_key'  => 'pdservicekey',
                        'incident_key' => check.name,
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

    let (:response) { {"incidents" =>
                       [{"incident_number" => 12,
                         "incident_key"=> check.name,
                         "status" => "acknowledged",
                         "last_status_change_by" => status_change}],
                       "limit"=>100,
                       "offset"=>0,
                       "total"=>1}
                     }

    it "doesn't look for acknowledgements if this search is already running" do
      expect(redis).to receive(:del).with('sem_pagerduty_acks_running')
      expect(redis).to receive(:quit)

      expect(Flapjack::Gateways::PagerDuty).to receive(:test_pagerduty_connection).and_return(true)

      expect(redis).to receive(:setnx).with('sem_pagerduty_acks_running', 'true').and_return(0)

      expect(Kernel).to receive(:sleep).with(10).and_raise(Flapjack::PikeletStop.new)

      expect(lock).to receive(:synchronize).and_yield

      fpa = Flapjack::Gateways::PagerDuty::AckFinder.new(:lock => lock,
        :config => config)
      expect { fpa.start }.to raise_error(Flapjack::PikeletStop)
    end

    it "looks for and creates acknowledgements if the search is not already running" do
      expect(redis).to receive(:del).with('sem_pagerduty_acks_running').twice
      expect(redis).to receive(:quit)

      expect(Flapjack::Gateways::PagerDuty).to receive(:test_pagerduty_connection).and_return(true)

      expect(redis).to receive(:setnx).with('sem_pagerduty_acks_running', 'true').and_return(1)
      expect(redis).to receive(:expire).with('sem_pagerduty_acks_running', 3600)

      expect(Flapjack::Data::Check).to receive(:lock).
        with(Flapjack::Data::ScheduledMaintenance, Flapjack::Data::UnscheduledMaintenance).
        and_yield

      check_scope = double('check_scope')
      expect(check_scope).to receive(:reject).
        and_yield(check).
        and_return([check])

      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:failing => true).and_return(check_scope)

      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:id => [check.id]).and_return(check_scope)

      expect(check).to receive(:in_unscheduled_maintenance?).
        with(an_instance_of(Time)).and_return(false)

      expect(check).to receive(:in_scheduled_maintenance?).
        with(an_instance_of(Time)).and_return(false)

      expect(Flapjack::Data::Medium).to receive(:lock).
        with(Flapjack::Data::Check, Flapjack::Data::Rule).
        and_yield

      medium = double(Flapjack::Data::Medium, :id => SecureRandom.uuid)
      expect(medium).to receive(:pagerduty_subdomain).and_return('mydomain')
      expect(medium).to receive(:pagerduty_token).and_return('abc')
      expect(medium).to receive(:pagerduty_ack_duration).and_return(nil)

      expect(medium).to receive(:checks).with(:initial_scope => check_scope,
        :time => an_instance_of(Time)).and_return(check_scope)

      expect(check_scope).to receive(:ids).and_return([check.id])

      media_scope = double('media_scope', :all => [medium])

      expect(Flapjack::Data::Medium).to receive(:intersect).
        with(:transport => 'pagerduty').and_return(media_scope)

      expect(Flapjack::Data::Event).to receive(:create_acknowledgements).with('events',
        [check],
        :summary => 'Acknowledged on PagerDuty by John Smith',
        :duration => 14400)

      expect(Kernel).to receive(:sleep).with(10).and_raise(Flapjack::PikeletStop.new)

      expect(lock).to receive(:synchronize).and_yield

      fpa = Flapjack::Gateways::PagerDuty::AckFinder.new(:lock => lock,
                                                         :config => config)
      expect(fpa).to receive(:pagerduty_acknowledgements).
        with(an_instance_of(Time), 'mydomain', 'abc', [check.name]).
        and_return(response['incidents'])
      expect { fpa.start }.to raise_error(Flapjack::PikeletStop)
    end

    # testing separately and stubbing above
    it "looks for acknowledgements via the PagerDuty API" do
      subdomain = 'mydomain'
      token = 'abc'

      since = (now.utc - (60*60*24*7)).iso8601 # the last week
      unt   = (now.utc + (60*60)).iso8601      # 1 hour in the future

      req = stub_request(:get, "https://#{subdomain}.pagerduty.com/api/v1/incidents").
            with(:headers => {'Content-type'  => 'application/json',
                              'Authorization' => "Token token=#{token}"},
                 :query => {
                   :fields => 'incident_key,incident_number,last_status_change_by',
                   :since => since, :until => unt, :status => 'acknowledged'
                 }
                ).
            to_return(:status => 200,
                      :body => Flapjack.dump_json(response),
                      :headers => {})

      expect(redis).to receive(:del).with('sem_pagerduty_acks_running')

      fpa = Flapjack::Gateways::PagerDuty::AckFinder.new(:config => config)
      result = fpa.send(:pagerduty_acknowledgements, now, subdomain, token, [check.name])
      expect(req).to have_been_requested

      expect(result).to be_a(Array)
      expect(result.size).to eq(1)
      incident = result.first
      expect(incident).to be_a(Hash)
      pg_acknowledged_by = incident['last_status_change_by']
      expect(pg_acknowledged_by).to be_a(Hash)
      expect(pg_acknowledged_by).to have_key('id')
      expect(pg_acknowledged_by['id']).to eq('ABCDEFG')
    end

    it 'gets all values in a paginated request for acknowledgements' do
      subdomain = 'mydomain'
      token = 'abc'

      since = (now.utc - (60*60*24*7)).iso8601 # the last week
      unt   = (now.utc + (60*60)).iso8601      # 1 hour in the future

      response_1 = {"incidents" => [{'incident_key' => check.name}] * 100,
                       "limit"  => 100,
                       "offset" => 0,
                       "total"  => 120}

      response_2 = {"incidents" => [{'incident_key' => check.name}] * 20,
                       "limit"  => 100,
                       "offset" => 100,
                       "total"  => 120}

      req = stub_request(:get, "https://#{subdomain}.pagerduty.com/api/v1/incidents").
            with(:headers => {'Content-type'  => 'application/json',
                              'Authorization' => "Token token=#{token}"},
                 :query => {
                   :fields => 'incident_key,incident_number,last_status_change_by',
                   :since => since, :until => unt, :status => 'acknowledged'
                 }
                ).
            to_return(:status => 200,
                      :body => Flapjack.dump_json(response_1),
                      :headers => {})

      req = stub_request(:get, "https://#{subdomain}.pagerduty.com/api/v1/incidents").
            with(:headers => {'Content-type'  => 'application/json',
                              'Authorization' => "Token token=#{token}"},
                 :query => {
                   :fields => 'incident_key,incident_number,last_status_change_by',
                   :since => since, :until => unt, :status => 'acknowledged',
                   :offset => 100, :limit => 100
                 }
                ).
            to_return(:status => 200,
                      :body => Flapjack.dump_json(response_2),
                      :headers => {})

      expect(redis).to receive(:del).with('sem_pagerduty_acks_running')

      fpa = Flapjack::Gateways::PagerDuty::AckFinder.new(:config => config)
      result = fpa.send(:pagerduty_acknowledgements, now, subdomain, token, [check.name])
      expect(req).to have_been_requested

      expect(result).to be_a(Array)
      expect(result.size).to eq(120)
    end

    it 'uses a smaller time period for follow-up requests' do
      subdomain = 'mydomain'
      token = 'abc'

      time_first  = now.utc
      time_second = (now + 10).utc

      since_first   = (time_first - (60 * 60 * 24 * 7)).iso8601 # the last week
      since_second  = (time_second - (60 * 15)).iso8601         # the last 15 minutes

      unt_first     = (time_first + (60 * 60)).iso8601          # 1 hour in the future
      unt_second    = (time_second + (60 * 60)).iso8601         # 1 hour in the future

      req_first = stub_request(:get, "https://#{subdomain}.pagerduty.com/api/v1/incidents").
            with(:headers => {'Content-type'  => 'application/json',
                              'Authorization' => "Token token=#{token}"},
                 :query => {
                   :fields => 'incident_key,incident_number,last_status_change_by',
                   :since => since_first, :until => unt_first, :status => 'acknowledged'
                 }
                ).
            to_return(:status => 200,
                      :body => Flapjack.dump_json(response),
                      :headers => {})

      req_second = stub_request(:get, "https://#{subdomain}.pagerduty.com/api/v1/incidents").
            with(:headers => {'Content-type'  => 'application/json',
                              'Authorization' => "Token token=#{token}"},
                 :query => {
                   :fields => 'incident_key,incident_number,last_status_change_by',
                   :since => since_second, :until => unt_second, :status => 'acknowledged'
                 }
                ).
            to_return(:status => 200,
                      :body => Flapjack.dump_json(response),
                      :headers => {})

      expect(redis).to receive(:del).with('sem_pagerduty_acks_running')

      fpa = Flapjack::Gateways::PagerDuty::AckFinder.new(:config => config)
      fpa.send(:pagerduty_acknowledgements, now, subdomain, token, [check.name])
      fpa.send(:pagerduty_acknowledgements, (now + 10), subdomain, token, [check.name])
      expect(req_first).to have_been_requested
      expect(req_second).to have_been_requested
    end

    it 'does not look for acknowledgements if no checks are failing & unacknowledged' do
      expect(redis).to receive(:del).with('sem_pagerduty_acks_running').twice
      expect(redis).to receive(:quit)

      expect(Flapjack::Gateways::PagerDuty).to receive(:test_pagerduty_connection).and_return(true)

      expect(redis).to receive(:setnx).with('sem_pagerduty_acks_running', 'true').and_return(1)
      expect(redis).to receive(:expire).with('sem_pagerduty_acks_running', 3600)

      expect(Flapjack::Data::Check).to receive(:lock).
        with(Flapjack::Data::ScheduledMaintenance, Flapjack::Data::UnscheduledMaintenance).
        and_yield

      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:failing => true).and_return([])

      expect(Flapjack::Data::Event).not_to receive(:create_acknowledgements)

      expect(Kernel).to receive(:sleep).with(10).and_raise(Flapjack::PikeletStop.new)

      expect(lock).to receive(:synchronize).and_yield

      fpa = Flapjack::Gateways::PagerDuty::AckFinder.new(:lock => lock,
                                                         :config => config)
      expect(fpa).not_to receive(:pagerduty_acknowledgements)
      expect { fpa.start }.to raise_error(Flapjack::PikeletStop)
    end
  end
end
