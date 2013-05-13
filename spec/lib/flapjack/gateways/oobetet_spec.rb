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
                  'rooms'    => ['flapjacktest@conference.example.com']
                 }
  }

  let(:stanza) { mock('stanza') }

  it "raises an error if a required config setting is not set" do
    Socket.should_receive(:gethostname).and_return('thismachine')

    fo = Flapjack::Gateways::Oobetet.new(:config => config.delete('watched_check'), :logger => @logger)

    lambda {
      fo.setup
    }.should raise_error
  end

  it "hooks up event handlers to the appropriate methods" do
    fo = Flapjack::Gateways::Oobetet.new(:config => config, :logger => @logger)

    EventMachine::should_receive(:next_tick).exactly(3).times.and_yield

    fo.should_receive(:register_handler).with(:ready).and_yield(stanza)
    fo.should_receive(:on_ready).with(stanza)

    fo.should_receive(:register_handler).with(:message, :groupchat?).and_yield(stanza)
    fo.should_receive(:on_groupchat).with(stanza)

    fo.should_receive(:register_handler).with(:disconnected).and_yield(stanza)
    fo.should_receive(:on_disconnect).with(stanza).and_return(true)

    fo.register_handlers
  end

  it "joins a chat room after connecting" do
    fo = Flapjack::Gateways::Oobetet.new(:config => config, :logger => @logger)

    fo.should_receive(:write).with(an_instance_of(Blather::Stanza::Presence))
    fo.should_receive(:write).with(an_instance_of(Blather::Stanza::Message))

    fo.on_ready(stanza)
  end

  it "reconnects when disconnected (if not quitting)" do
    fo = Flapjack::Gateways::Oobetet.new(:config => config, :logger => @logger)

    EventMachine::Timer.should_receive(:new).with(1).and_yield
    fo.should_receive(:connect)

    ret = fo.on_disconnect(stanza)
    ret.should be_true
  end

  it "records times of a problem status messages" do
    fo = Flapjack::Gateways::Oobetet.new(:config => config, :logger => @logger)
    fo.setup

    t = Time.now

    stanza.should_receive(:body).and_return( %q{PROBLEM: "PING" on foo.bar.net} )
    Time.should_receive(:now).and_return(t)

    fo.on_groupchat(stanza)
    fo_times = fo.instance_variable_get('@times')
    fo_times.should_not be_nil
    fo_times.should have_key(:last_problem)
    fo_times[:last_problem].should == t.to_i
  end

  it "records times of a recovery status messages" do
    fo = Flapjack::Gateways::Oobetet.new(:config => config, :logger => @logger)
    fo.setup

    t = Time.now

    stanza.should_receive(:body).and_return( %q{RECOVERY: "PING" on foo.bar.net} )
    Time.should_receive(:now).and_return(t)

    fo.on_groupchat(stanza)
    fo_times = fo.instance_variable_get('@times')
    fo_times.should_not be_nil
    fo_times.should have_key(:last_recovery)
    fo_times[:last_recovery].should == t.to_i
  end

  it "records times of an acknowledgement status messages" do
    fo = Flapjack::Gateways::Oobetet.new(:config => config, :logger => @logger)
    fo.setup

    t = Time.now

    stanza.should_receive(:body).and_return( %q{ACKNOWLEDGEMENT: "PING" on foo.bar.net} )
    Time.should_receive(:now).and_return(t)

    fo.on_groupchat(stanza)
    fo_times = fo.instance_variable_get('@times')
    fo_times.should_not be_nil
    fo_times.should have_key(:last_ack)
    fo_times[:last_ack].should == t.to_i
  end

  it "runs a loop checking for recorded problems" do
    timer = mock('timer')
    timer.should_receive(:cancel)
    EventMachine.should_receive(:add_periodic_timer).with(60).and_return(timer)

    fo = Flapjack::Gateways::Oobetet.new(:config => config, :logger => @logger)
    fo.should_receive(:register_handler).exactly(3).times
    fo.should_receive(:connect)

    Kernel.should_receive(:sleep).with(10) {
      fo.instance_variable_set('@should_quit', true)
      nil
    }

    fo.start
  end

end
