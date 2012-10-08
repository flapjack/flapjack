require 'spec_helper'
require 'flapjack/oobetet'

describe Flapjack::Oobetet do

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

    fo = Flapjack::Oobetet.new
    fo.bootstrap(:config => config.delete('watched_check'))

    lambda {
      fo.setup
    }.should raise_error
  end

  it "hooks up event handlers to the appropriate methods" do
    Socket.should_receive(:gethostname).and_return('thismachine')

    fo = Flapjack::Oobetet.new
    fo.bootstrap(:config => config)

    EM.should_receive(:next_tick).exactly(3).times.and_yield
    EM.should_receive(:synchrony).exactly(3).times.and_yield

    fo.should_receive(:register_handler).with(:ready).and_yield(stanza)
    fo.should_receive(:on_ready).with(stanza)

    fo.should_receive(:register_handler).with(:message, :groupchat?).and_yield(stanza)
    fo.should_receive(:on_groupchat).with(stanza)

    fo.should_receive(:register_handler).with(:disconnected).and_yield(stanza)
    fo.should_receive(:on_disconnect).with(stanza).and_return(true)

    fo.setup
  end

  it "joins a chat room after connecting" do
    fo = Flapjack::Oobetet.new
    fo.bootstrap(:config => config)

    fo.should_receive(:write).with(an_instance_of(Blather::Stanza::Presence))
    fo.should_receive(:write).with(an_instance_of(Blather::Stanza::Message))

    fo.on_ready(stanza)
  end

  it "reconnects when disconnected (if not quitting)" do
    fo = Flapjack::Oobetet.new
    fo.bootstrap(:config => config)

    EventMachine::Timer.should_receive(:new).with(1).and_yield
    fo.should_receive(:connect)

    ret = fo.on_disconnect(stanza)
    ret.should be_true
  end

  it "runs a loop checking for recorded problems" do
    timer = mock('timer')
    timer.should_receive(:cancel)
    EM::Synchrony.should_receive(:add_periodic_timer).with(60).and_return(timer)

    fo = Flapjack::Oobetet.new
    fo.bootstrap(:config => config)
    fo.should_receive(:register_handler).exactly(3).times

    fo.should_receive(:connect)
    fo.should_receive(:should_quit?).twice.and_return(false, true)

    EM::Synchrony.should_receive(:sleep).with(10)

    fo.main
  end

end
