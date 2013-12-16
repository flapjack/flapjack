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

  let(:stanza) { double('stanza') }

  it "raises an error if a required config setting is not set" do
    expect(Socket).to receive(:gethostname).and_return('thismachine')

    fo = Flapjack::Gateways::Oobetet.new(:config => config.delete('watched_check'), :logger => @logger)

    expect {
      fo.setup
    }.to raise_error
  end

  it "hooks up event handlers to the appropriate methods" do
    fo = Flapjack::Gateways::Oobetet.new(:config => config, :logger => @logger)

    expect(EventMachine::Synchrony).to receive(:next_tick).exactly(3).times.and_yield

    expect(fo).to receive(:register_handler).with(:ready).and_yield(stanza)
    expect(fo).to receive(:on_ready).with(stanza)

    expect(fo).to receive(:register_handler).with(:message, :groupchat?).and_yield(stanza)
    expect(fo).to receive(:on_groupchat).with(stanza)

    expect(fo).to receive(:register_handler).with(:disconnected).and_yield(stanza)
    expect(fo).to receive(:on_disconnect).with(stanza).and_return(true)

    fo.register_handlers
  end

  it "joins a chat room after connecting" do
    fo = Flapjack::Gateways::Oobetet.new(:config => config, :logger => @logger)

    expect(fo).to receive(:write).with(an_instance_of(Blather::Stanza::Presence))
    expect(fo).to receive(:write).with(an_instance_of(Blather::Stanza::Message))

    fo.on_ready(stanza)
  end

  it "reconnects when disconnected (if not quitting)" do
    fo = Flapjack::Gateways::Oobetet.new(:config => config, :logger => @logger)

    expect(EventMachine::Timer).to receive(:new).with(1).and_yield
    expect(fo).to receive(:connect)

    ret = fo.on_disconnect(stanza)
    expect(ret).to be true
  end

  it "records times of a problem status messages" do
    fo = Flapjack::Gateways::Oobetet.new(:config => config, :logger => @logger)
    fo.setup

    t = Time.now

    expect(stanza).to receive(:body).and_return( %q{PROBLEM: "PING" on foo.bar.net} )
    expect(Time).to receive(:now).and_return(t)

    fo.on_groupchat(stanza)
    fo_times = fo.instance_variable_get('@times')
    expect(fo_times).not_to be_nil
    expect(fo_times).to have_key(:last_problem)
    expect(fo_times[:last_problem]).to eq(t.to_i)
  end

  it "records times of a recovery status messages" do
    fo = Flapjack::Gateways::Oobetet.new(:config => config, :logger => @logger)
    fo.setup

    t = Time.now

    expect(stanza).to receive(:body).and_return( %q{RECOVERY: "PING" on foo.bar.net} )
    expect(Time).to receive(:now).and_return(t)

    fo.on_groupchat(stanza)
    fo_times = fo.instance_variable_get('@times')
    expect(fo_times).not_to be_nil
    expect(fo_times).to have_key(:last_recovery)
    expect(fo_times[:last_recovery]).to eq(t.to_i)
  end

  it "records times of an acknowledgement status messages" do
    fo = Flapjack::Gateways::Oobetet.new(:config => config, :logger => @logger)
    fo.setup

    t = Time.now

    expect(stanza).to receive(:body).and_return( %q{ACKNOWLEDGEMENT: "PING" on foo.bar.net} )
    expect(Time).to receive(:now).and_return(t)

    fo.on_groupchat(stanza)
    fo_times = fo.instance_variable_get('@times')
    expect(fo_times).not_to be_nil
    expect(fo_times).to have_key(:last_ack)
    expect(fo_times[:last_ack]).to eq(t.to_i)
  end

  it "runs a loop checking for recorded problems" do
    timer = double('timer')
    expect(timer).to receive(:cancel)
    expect(EM::Synchrony).to receive(:add_periodic_timer).with(60).and_return(timer)

    fo = Flapjack::Gateways::Oobetet.new(:config => config, :logger => @logger)
    expect(fo).to receive(:register_handler).exactly(3).times
    expect(fo).to receive(:connect)

    expect(EM::Synchrony).to receive(:sleep).with(10) {
      fo.instance_variable_set('@should_quit', true)
      nil
    }

    fo.start
  end

end
