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

    let(:now) { Time.now }

    it "starts and is stopped by a signal"

    it "records times of a problem status message" do
      fo = Flapjack::Gateways::Oobetet::TimeChecker.new(:config => config, :logger => @logger)
      fo.send(:receive_status, 'problem', now.to_i)
      fo_times = fo.instance_variable_get('@times')
      fo_times.should_not be_nil
      fo_times.should have_key(:last_problem)
      fo_times[:last_problem].should == now.to_i
    end

    it "records times of a recovery status message" do
      fo = Flapjack::Gateways::Oobetet::TimeChecker.new(:config => config, :logger => @logger)
      fo.send(:receive_status, 'recovery', now.to_i)
      fo_times = fo.instance_variable_get('@times')
      fo_times.should_not be_nil
      fo_times.should have_key(:last_recovery)
      fo_times[:last_recovery].should == now.to_i
    end

    it "records times of an acknowledgement status message" do
      fo = Flapjack::Gateways::Oobetet::TimeChecker.new(:config => config, :logger => @logger)
      fo.send(:receive_status, 'acknowledgement', now.to_i)
      fo_times = fo.instance_variable_get('@times')
      fo_times.should_not be_nil
      fo_times.should have_key(:last_ack)
      fo_times[:last_ack].should == now.to_i
    end

  end

  context 'XMPP' do

    it "raises an error if a required config setting is not set" do
      lambda {
        Flapjack::Gateways::Oobetet::Bot.new(:config => config.delete('watched_check'), :logger => @logger)
      }.should raise_error
    end

    it "starts and is stopped by a signal"

    it "announces to jabber rooms"

  end

end
