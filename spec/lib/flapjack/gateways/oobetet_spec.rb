require 'spec_helper'
require 'flapjack/gateways/oobetet'

describe Flapjack::Gateways::Oobetet, :logger => true do

  let(:config) { {'server'   => 'example.com',
                  'port'     => '5222',
                  'jabberid' => 'flapjack@example.com',
                  'password' => 'password',
                  'alias'    => 'flapjack',
                  'watched_check'  => 'PING',
                  'watched_entity' => 'foo.bar.net',
                  'pagerduty_contact' => 'pdservicekey',
                  'rooms'    => ['flapjacktest@conference.example.com']
                 }
  }

  let(:now) { Time.now }

  let(:lock) { double(Monitor) }

  context 'notifications' do

    it "raises an error if a required config setting is not set" do
      expect {
        Flapjack::Gateways::Oobetet::Notifier.new(:config => config.delete('watched_check'))
      }.to raise_error("Flapjack::Oobetet: watched_check must be defined in the config")
    end

    it "starts and is stopped by an exception" do
      expect(Kernel).to receive(:sleep).with(10).and_raise(Flapjack::PikeletStop)

      expect(lock).to receive(:synchronize).and_yield

      fon = Flapjack::Gateways::Oobetet::Notifier.new(:lock => lock,
        :config => config)
      expect(fon).to receive(:check_timers)
      expect { fon.start }.to raise_error(Flapjack::PikeletStop)
    end

    it "checks for a breach and emits notifications" do
      time_check = double(Flapjack::Gateways::Oobetet::TimeChecker)
      expect(time_check).to receive(:respond_to?).with(:announce).and_return(false)
      expect(time_check).to receive(:respond_to?).with(:breach?).and_return(true)
      expect(time_check).to receive(:breach?).
        and_return("haven't seen a test problem notification in the last 300 seconds")

      bot = double(Flapjack::Gateways::Oobetet::Bot)
      expect(bot).to receive(:respond_to?).with(:announce).and_return(true)
      expect(bot).to receive(:announce).with(/^Flapjack Self Monitoring is Critical/)

      # TODO be more specific about the request body
      req = stub_request(:post, "https://events.pagerduty.com/generic/2010-04-15/create_event.json").
         to_return(:status => 200, :body => Flapjack.dump_json('status' => 'success'))

      fon = Flapjack::Gateways::Oobetet::Notifier.new(:lock => lock, :config => config)
      fon.instance_variable_set('@siblings', [time_check, bot])
      fon.send(:check_timers)

      expect(req).to have_been_requested
    end

  end

  context 'time checking' do

    let(:now)          { Time.now }
    let(:a_minute_ago) { now.to_i - 60 }
    let(:a_day_ago)    { now.to_i - (60 * 60 * 24) }

    it "starts and is stopped by a signal" do
      expect(lock).to receive(:synchronize).and_yield
      stop_cond = double(MonitorMixin::ConditionVariable)
      expect(stop_cond).to receive(:wait_until)

      fot = Flapjack::Gateways::Oobetet::TimeChecker.new(:lock => lock, :stop_condition => stop_cond,
        :config => config)
      fot.start
    end

    it "records times of a problem status message" do
      expect(lock).to receive(:synchronize).and_yield
      fot = Flapjack::Gateways::Oobetet::TimeChecker.new(:lock => lock, :config => config)
      fot.send(:receive_status, 'problem', now.to_i)
      fot_times = fot.instance_variable_get('@times')
      expect(fot_times).not_to be_nil
      expect(fot_times).to have_key(:last_problem)
      expect(fot_times[:last_problem]).to eq(now.to_i)
    end

    it "records times of a recovery status message" do
      expect(lock).to receive(:synchronize).and_yield
      fot = Flapjack::Gateways::Oobetet::TimeChecker.new(:lock => lock, :config => config)
      fot.send(:receive_status, 'recovery', now.to_i)
      fot_times = fot.instance_variable_get('@times')
      expect(fot_times).not_to be_nil
      expect(fot_times).to have_key(:last_recovery)
      expect(fot_times[:last_recovery]).to eq(now.to_i)
    end

    it "records times of an acknowledgement status message" do
      expect(lock).to receive(:synchronize).and_yield
      fot = Flapjack::Gateways::Oobetet::TimeChecker.new(:lock => lock, :config => config)
      fot.send(:receive_status, 'acknowledgement', now.to_i)
      fot_times = fot.instance_variable_get('@times')
      expect(fot_times).not_to be_nil
      expect(fot_times).to have_key(:last_ack)
      expect(fot_times[:last_ack]).to eq(now.to_i)
    end

    it "detects a time period with no test problem alerts" do
      expect(lock).to receive(:synchronize).and_yield
      fot = Flapjack::Gateways::Oobetet::TimeChecker.new(:lock => lock, :config => config)
      fot_times = fot.instance_variable_get('@times')

      fot_times[:last_problem]  = a_day_ago
      fot_times[:last_recovery] = a_minute_ago
      fot_times[:last_ack]      = a_minute_ago
      fot_times[:last_ack_sent] = a_minute_ago

      breach = fot.breach?(now.to_i)
      expect(breach).not_to be_nil
      expect(breach).to eq("haven't seen a test problem notification in the last 300 seconds")
    end

    it "detects a time period with no test recovery alerts" do
      expect(lock).to receive(:synchronize).and_yield
      fot = Flapjack::Gateways::Oobetet::TimeChecker.new(:lock => lock, :config => config)
      fot_times = fot.instance_variable_get('@times')

      fot_times[:last_problem]  = a_minute_ago
      fot_times[:last_recovery] = a_day_ago
      fot_times[:last_ack]      = a_minute_ago
      fot_times[:last_ack_sent] = a_minute_ago

      breach = fot.breach?(now.to_i)
      expect(breach).not_to be_nil
      expect(breach).to eq("haven't seen a test recovery notification in the last 300 seconds")
    end

  end

  context 'XMPP' do

    let(:muc_client) { double(::Jabber::MUC::SimpleMUCClient) }

    it "raises an error if a required config setting is not set" do
      expect {
        Flapjack::Gateways::Oobetet::Bot.new(:config => config.delete('watched_check'))
      }.to raise_error("Flapjack::Oobetet: watched_check must be defined in the config")
    end

    it "starts and is stopped by a signal" do
      t = now.to_i

      time_checker = double(Flapjack::Gateways::Oobetet::TimeChecker)
      expect(time_checker).to receive(:respond_to?).with(:receive_status).and_return(true)
      expect(time_checker).to receive(:receive_status).with('recovery', t)

      client = double(::Jabber::Client)
      expect(client).to receive(:connect)
      expect(client).to receive(:auth).with('password')
      expect(client).to receive(:send).with(an_instance_of(::Jabber::Presence))

      expect(muc_client).to receive(:on_message).and_yield(t, 'test', 'Recovery "PING" on foo.bar.net')
      expect(muc_client).to receive(:join).with('flapjacktest@conference.example.com/flapjack')
      expect(muc_client).to receive(:say).with(/^flapjack oobetet gateway started/)

      expect(muc_client).to receive(:active?).and_return(true)
      expect(muc_client).to receive(:exit)

      expect(client).to receive(:close)

      expect(::Jabber::Client).to receive(:new).and_return(client)
      expect(::Jabber::MUC::SimpleMUCClient).to receive(:new).and_return(muc_client)

      expect(lock).to receive(:synchronize).and_yield
      stop_cond = double(MonitorMixin::ConditionVariable)
      expect(stop_cond).to receive(:wait_until)

      fob = Flapjack::Gateways::Oobetet::Bot.new(:lock => lock, :stop_condition => stop_cond,
        :config => config)
      fob.instance_variable_set('@siblings', [time_checker])
      fob.start
    end

    it "announces to jabber rooms" do
      muc_client2 = double(::Jabber::MUC::SimpleMUCClient)

      expect(muc_client).to receive(:say).with('hello!')
      expect(muc_client2).to receive(:say).with('hello!')

      expect(lock).to receive(:synchronize).and_yield

      fob = Flapjack::Gateways::Oobetet::Bot.new(:lock => lock, :config => config)
      fob.instance_variable_set('@muc_clients', {'room1' => muc_client, 'room2' => muc_client2})
      fob.announce('hello!')
    end

  end

end
