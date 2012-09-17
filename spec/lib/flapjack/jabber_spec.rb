require 'spec_helper'
require 'flapjack/jabber'

describe Flapjack::Jabber do

  let(:config) { {'queue'    => 'jabber_notifications',
                  'server'   => 'example.com',
                  'port'     => '5222',
                  'jabberid' => 'flapjack@example.com',
                  'password' => 'password',
                  'alias'    => 'flapjack',
                  'rooms'    => ['flapjacktest@conference.example.com']
                 }
  }

  let(:stanza) { mock('stanza') }

  it "is initialized" do
    fj = Flapjack::Jabber.new(:config => config)
    fj.should_not be_nil
  end

  it "hooks up event handlers to the appropriate methods" do
    Socket.should_receive(:gethostname).and_return('thismachine')

    fj = Flapjack::Jabber.new(:config => config)

    fj.should_receive(:register_handler).with(:ready).and_yield(stanza)
    fj.should_receive(:on_ready).with(stanza)

    fj.should_receive(:register_handler).with(:message, :groupchat?, :body => /^flapjack:\s+/).and_yield(stanza)
    fj.should_receive(:on_groupchat).with(stanza)

    fj.should_receive(:register_handler).with(:disconnected).and_yield(stanza)
    fj.should_receive(:on_disconnect).with(stanza).and_return(true)

    fj.setup
  end

  it "joins a chat room after connecting" do
    fj = Flapjack::Jabber.new(:config => config)

    fj.should_receive(:write).with(an_instance_of(Blather::Stanza::Presence))
    fj.should_receive(:write).with(an_instance_of(Blather::Stanza::Message))

    fj.on_ready(stanza)
  end

  it "receives an acknowledgement message" do
    stanza.should_receive(:body).and_return('flapjack: ACKID 876 fixing now')
    from = mock('from')
    from.should_receive(:stripped).and_return('sender')
    stanza.should_receive(:from).and_return(from)

    redis = mock('redis')
    redis.should_receive(:hget).with('unacknowledged_failures', '876').
      and_return('main-example.com:ping')
    ::Redis.should_receive(:new).and_return(redis)

    entity_check = mock(Flapjack::Data::EntityCheck)
    entity_check.should_receive(:create_acknowledgement).
      with('summary' => 'fixing now', 'acknowledgement_id' => '876')
    entity_check.should_receive(:entity_name).and_return('main-example.com')
    entity_check.should_receive(:check).and_return('ping')

    Flapjack::Data::EntityCheck.should_receive(:for_event_id).
      with('main-example.com:ping', :redis => redis).
      and_return(entity_check)

    fj = Flapjack::Jabber.new(:config => config)

    EM.should_receive(:next_tick).and_yield
    fj.should_receive(:write).with(an_instance_of(Blather::Stanza::Message))

    fj.on_groupchat(stanza)
  end

  it "receives a message it doesn't understand" do
    stanza.should_receive(:body).twice.and_return('flapjack: hello!')
    from = mock('from')
    from.should_receive(:stripped).and_return('sender')
    stanza.should_receive(:from).and_return(from)

    fj = Flapjack::Jabber.new(:config => config)

    EM.should_receive(:next_tick).and_yield
    fj.should_receive(:write).with(an_instance_of(Blather::Stanza::Message))

    fj.on_groupchat(stanza)
  end

  it "reconnects when disconnected (if not quitting)" do
    fj = Flapjack::Jabber.new(:config => config)

    EventMachine::Timer.should_receive(:new).with(1).and_yield
    fj.should_receive(:connect)

    ret = fj.on_disconnect(stanza)
    ret.should be_true
  end

  it "prompts the blocking redis connection to quit" do
    redis = mock('redis')
    ::Redis.should_receive(:new).and_return(redis)
    redis.should_receive(:rpush).with('jabber_notifications', %q{{"notification_type":"shutdown"}})
    redis.should_receive(:quit)

    fj = Flapjack::Jabber.new(:config => config)

    fj.add_shutdown_event
  end

  it "runs a blocking loop listening for notifications" do
    EM::Synchrony.should_receive(:add_periodic_timer).with(30)
    EM::Synchrony.should_receive(:add_periodic_timer).with(60)

    redis = mock('redis')
    fj = Flapjack::Jabber.new(:config => config, :redis => redis)

    fj.should_receive(:connect)
    fj.should_receive(:connected?).twice.and_return(true)
    fj.should_receive(:should_quit?).exactly(3).times.and_return(false, false, true)
    redis.should_receive(:blpop).twice.and_return(
      ["jabber_notifications", %q{{"notification_type":"problem","event_id":"main-example.com:ping","state":"critical","summary":"!!!"}}],
      ["jabber_notifications", %q{{"notification_type":"shutdown"}}]
    )

    EM.should_receive(:next_tick).twice.and_yield
    fj.should_receive(:write).with(an_instance_of(Blather::Stanza::Message))
    fj.should_receive(:close)

    fj.main
  end

end