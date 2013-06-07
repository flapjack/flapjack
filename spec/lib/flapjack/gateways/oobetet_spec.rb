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
    lambda {
      Flapjack::Gateways::Oobetet::Bot.new(:config => config.delete('watched_check'), :logger => @logger)
    }.should raise_error
    lambda {
      Flapjack::Gateways::Oobetet::Notifier.new(:config => config.delete('watched_check'), :logger => @logger)
    }.should raise_error
  end

  it "hooks up event handlers to the appropriate methods" do
    Socket.should_receive(:gethostname).and_return('thismachine')

    pid = 23
    Process.should_receive(:pid).and_return(pid)

    jid = mock(::Blather::JID)
    ::Blather::JID.should_receive(:new).
      with("flapjack@example.com/thismachine:#{pid}").and_return(jid)

    client = mock(Blather::Client)
    client.should_receive(:clear_handlers).with(:error)
    error = mock(Exception)
    error.should_receive(:message).and_return('oh no')
    client.should_receive(:register_handler).with(:error).and_yield(error)

    foc = mock(Flapjack::Gateways::Oobetet::BotClient)
    foc.should_receive(:setup).with(jid, 'password', 'example.com', 5222)
    foc.should_receive(:client).and_return(client)
    foc.should_receive(:run)
    Flapjack::Gateways::Oobetet::BotClient.should_receive(:new).and_return(foc)

    fo = Flapjack::Gateways::Oobetet::Bot.new(:config => config, :logger => @logger)

    fo.should_receive(:on_ready).with(stanza)
    foc.should_receive(:when_ready).and_yield(stanza)

    fo.should_receive(:on_groupchat).with(stanza)
    foc.should_receive(:message).with(:groupchat?).and_yield(stanza)

    fo.should_receive(:on_disconnect).with(stanza).and_return(true)
    foc.should_receive(:disconnected).and_yield(stanza)

    fo.start
  end

  it "joins a chat room after connecting" do
    fo = Flapjack::Gateways::Oobetet::Bot.new(:config => config, :logger => @logger)

    foc = mock(Flapjack::Gateways::Oobetet::BotClient)
    foc.should_receive(:write_to_stream).with(an_instance_of(Blather::Stanza::Presence))
    foc.should_receive(:say).with(config['rooms'].first, an_instance_of(String), :groupchat)

    fo = Flapjack::Gateways::Oobetet::Bot.new(:config => config, :logger => @logger)
    fo.instance_variable_set('@client', foc)

    kat = mock(EventMachine::PeriodicTimer)
    EventMachine.should_receive(:add_periodic_timer).with(60).and_yield.and_return(kat)
    foc.should_receive(:connected?).and_return(true)
    foc.should_receive(:write).with(' ')

    fo.send(:on_ready, stanza)
  end

  it "reconnects when disconnected (if not quitting)" do
    kat = mock(EventMachine::PeriodicTimer)
    kat.should_receive(:cancel)

    foc = mock(Flapjack::Gateways::Oobetet::BotClient)
    fo = Flapjack::Gateways::Oobetet::Bot.new(:config => config, :logger => @logger)
    fo.instance_variable_set('@client', foc)
    fo.instance_variable_set('@keepalive_timer', kat)

    EM::Timer.should_receive(:new).with(1).and_yield
    foc.should_receive(:run)

    ret = fo.send(:on_disconnect, stanza)
    ret.should be_true
  end

  it "records times of a problem status message" do
    t = Time.now

    stanza.should_receive(:body).and_return( %q{PROBLEM: "PING" on foo.bar.net} )
    Time.should_receive(:now).and_return(t)

    fo = Flapjack::Gateways::Oobetet::Bot.new(:config => config, :logger => @logger)
    fo.send(:on_groupchat, stanza)
    fo_times = fo.instance_variable_get('@times')
    fo_times.should_not be_nil
    fo_times.should have_key(:last_problem)
    fo_times[:last_problem].should == t.to_i
  end

  it "records times of a recovery status message" do
    t = Time.now

    stanza.should_receive(:body).and_return( %q{RECOVERY: "PING" on foo.bar.net} )

    fo = Flapjack::Gateways::Oobetet::Bot.new(:config => config, :logger => @logger)
    fo.send(:on_groupchat, stanza)
    fo_times = fo.instance_variable_get('@times')
    fo_times.should_not be_nil
    fo_times.should have_key(:last_recovery)
    fo_times[:last_recovery].should == t.to_i
  end

  it "records times of an acknowledgement status message" do
    t = Time.now

    stanza.should_receive(:body).and_return( %q{ACKNOWLEDGEMENT: "PING" on foo.bar.net} )

    fo = Flapjack::Gateways::Oobetet::Bot.new(:config => config, :logger => @logger)
    fo.send(:on_groupchat, stanza)
    fo_times = fo.instance_variable_get('@times')
    fo_times.should_not be_nil
    fo_times.should have_key(:last_ack)
    fo_times[:last_ack].should == t.to_i
  end

  it "runs a loop checking for recorded problems" do
    EventMachine.should_receive(:add_periodic_timer).with(10).and_yield

    fo = Flapjack::Gateways::Oobetet::Notifier.new(:config => config, :logger => @logger)
    fo.should_receive(:check_timers)
    fo.start
  end

  it "checks timer values from the jabber client"

end
