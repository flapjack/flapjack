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

  context 'notifications' do

    it "raises an error if a required config setting is not set" do
      lambda {
        Flapjack::Gateways::Oobetet::Notifier.new(:config => config.delete('watched_check'), :logger => @logger)
      }.should raise_error
    end

    it "starts and is stopped by an exception" do
      Kernel.should_receive(:sleep).with(10).and_raise(Flapjack::PikeletStop)

      fon = Flapjack::Gateways::Oobetet::Notifier.new(:config => config, :logger => @logger)
      fon.should_receive(:check_timers)
      fon.start
    end

    it "checks for a breach and emits notifications" do
      time_check = mock(Flapjack::Gateways::Oobetet::TimeChecker)
      time_check.should_receive(:respond_to?).with(:announce).and_return(false)
      time_check.should_receive(:respond_to?).with(:breach?).and_return(true)
      time_check.should_receive(:breach?).
        and_return("haven't seen a test problem notification in the last 300 seconds")

      bot = mock(Flapjack::Gateways::Oobetet::Bot)
      bot.should_receive(:respond_to?).with(:announce).and_return(true)
      bot.should_receive(:announce).with(/^Flapjack Self Monitoring is Critical/)

      # TODO be more specific about the request body
      stub_request(:post, "https://events.pagerduty.com/generic/2010-04-15/create_event.json").
         to_return(:status => 200, :body => {'status' => 'success'}.to_json)

      fon = Flapjack::Gateways::Oobetet::Notifier.new(:config => config, :logger => @logger)
      fon.instance_variable_set('@siblings', [time_check, bot])
      fon.send(:check_timers)
    end

  end

  context 'time checking' do

    let(:now)          { Time.now }
    let(:a_minute_ago) { now.to_i - 60 }
    let(:a_day_ago)    { now.to_i - (60 * 60 * 24) }

    it "starts and is stopped by a signal" do
      fot = Flapjack::Gateways::Oobetet::TimeChecker.new(:config => config, :logger => @logger)
      fot.instance_variable_get('@shutdown_cond').should_receive(:wait_until)
      fot.start
    end

    it "records times of a problem status message" do
      fot = Flapjack::Gateways::Oobetet::TimeChecker.new(:config => config, :logger => @logger)
      fot.send(:receive_status, 'problem', now.to_i)
      fot_times = fot.instance_variable_get('@times')
      fot_times.should_not be_nil
      fot_times.should have_key(:last_problem)
      fot_times[:last_problem].should == now.to_i
    end

    it "records times of a recovery status message" do
      fot = Flapjack::Gateways::Oobetet::TimeChecker.new(:config => config, :logger => @logger)
      fot.send(:receive_status, 'recovery', now.to_i)
      fot_times = fot.instance_variable_get('@times')
      fot_times.should_not be_nil
      fot_times.should have_key(:last_recovery)
      fot_times[:last_recovery].should == now.to_i
    end

    it "records times of an acknowledgement status message" do
      fot = Flapjack::Gateways::Oobetet::TimeChecker.new(:config => config, :logger => @logger)
      fot.send(:receive_status, 'acknowledgement', now.to_i)
      fot_times = fot.instance_variable_get('@times')
      fot_times.should_not be_nil
      fot_times.should have_key(:last_ack)
      fot_times[:last_ack].should == now.to_i
    end

    it "detects a time period with no test problem alerts" do
      fot = Flapjack::Gateways::Oobetet::TimeChecker.new(:config => config, :logger => @logger)
      fot_times = fot.instance_variable_get('@times')

      fot_times[:last_problem]  = a_day_ago
      fot_times[:last_recovery] = a_minute_ago
      fot_times[:last_ack]      = a_minute_ago
      fot_times[:last_ack_sent] = a_minute_ago

      breach = fot.breach?(now.to_i)
      breach.should_not be_nil
      breach.should == "haven't seen a test problem notification in the last 300 seconds"
    end

    it "detects a time period with no test recovery alerts" do
      fot = Flapjack::Gateways::Oobetet::TimeChecker.new(:config => config, :logger => @logger)
      fot_times = fot.instance_variable_get('@times')

      fot_times[:last_problem]  = a_minute_ago
      fot_times[:last_recovery] = a_day_ago
      fot_times[:last_ack]      = a_minute_ago
      fot_times[:last_ack_sent] = a_minute_ago

      breach = fot.breach?(now.to_i)
      breach.should_not be_nil
      breach.should == "haven't seen a test recovery notification in the last 300 seconds"
    end

  end

  context 'XMPP' do

    let(:muc_client) { mock(::Jabber::MUC::SimpleMUCClient) }

    it "raises an error if a required config setting is not set" do
      lambda {
        Flapjack::Gateways::Oobetet::Bot.new(:config => config.delete('watched_check'), :logger => @logger)
      }.should raise_error
    end

    it "starts and is stopped by a signal" do
      t = now.to_i

      time_checker = mock(Flapjack::Gateways::Oobetet::TimeChecker)
      time_checker.should_receive(:respond_to?).with(:receive_status).and_return(true)
      time_checker.should_receive(:receive_status).with('recovery', t)

      client = mock(::Jabber::Client)
      client.should_receive(:connect)
      client.should_receive(:auth).with('password')
      client.should_receive(:send).with(an_instance_of(::Jabber::Presence))

      muc_client.should_receive(:on_message).and_yield(t, 'test', 'Recovery "PING" on foo.bar.net')
      muc_client.should_receive(:join).with('flapjacktest@conference.example.com/flapjack')
      muc_client.should_receive(:say).with(/^flapjack oobetet gateway started/)

      muc_client.should_receive(:active?).and_return(true)
      muc_client.should_receive(:exit)

      client.should_receive(:close)

      ::Jabber::Client.should_receive(:new).and_return(client)
      ::Jabber::MUC::SimpleMUCClient.should_receive(:new).and_return(muc_client)

      fob = Flapjack::Gateways::Oobetet::Bot.new(:config => config, :logger => @logger)
      fob.instance_variable_set('@siblings', [time_checker])
      fob.instance_variable_get('@shutdown_cond').should_receive(:wait_until)
      fob.start
    end

    it "announces to jabber rooms" do
      muc_client2 = mock(::Jabber::MUC::SimpleMUCClient)

      muc_client.should_receive(:say).with('hello!')
      muc_client2.should_receive(:say).with('hello!')

      fob = Flapjack::Gateways::Oobetet::Bot.new(:config => config, :logger => @logger)
      fob.instance_variable_set('@muc_clients', {'room1' => muc_client, 'room2' => muc_client2})
      fob.announce('hello!')
    end

  end

end
