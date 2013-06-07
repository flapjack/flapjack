require 'spec_helper'
require 'flapjack/gateways/jabber'

describe Flapjack::Gateways::Jabber, :logger => true do

  let(:config) { {'queue'    => 'jabber_notifications',
                  'server'   => 'example.com',
                  'port'     => '5222',
                  'jabberid' => 'flapjack@example.com',
                  'password' => 'password',
                  'alias'    => 'flapjack',
                  'rooms'    => ['flapjacktest@conference.example.com']
                 }
  }

  let(:fiber) { mock(Fiber) }

  let(:stanza) { mock('stanza') }

  it "hooks up event handlers to the appropriate methods" do
    Socket.should_receive(:gethostname).and_return('thismachine')

    ::Redis.should_receive(:new)

    jid = mock(::Blather::JID)
    ::Blather::JID.should_receive(:new).
      with('flapjack@example.com/thismachine').and_return(jid)

    client = mock(Blather::Client)
    client.should_receive(:clear_handlers).with(:error)
    error = mock(Exception)
    error.should_receive(:message).and_return('oh no')
    client.should_receive(:register_handler).with(:error).and_yield(error)

    fjc = mock(Flapjack::Gateways::Jabber::BotClient)
    fjc.should_receive(:setup).with(jid, 'password', 'example.com', 5222)
    fjc.should_receive(:client).and_return(client)
    fjc.should_receive(:run)
    Flapjack::Gateways::Jabber::BotClient.should_receive(:new).and_return(fjc)

    fj = Flapjack::Gateways::Jabber::Bot.new(:config => config, :logger => @logger)

    fj.should_receive(:on_ready).with(stanza)
    fjc.should_receive(:when_ready).and_yield(stanza)

    fj.should_receive(:on_groupchat).with(stanza)
    fjc.should_receive(:message).with(:groupchat?, :body => /^flapjack:\s+/).and_yield(stanza)

    fj.should_receive(:on_chat).with(stanza)
    fjc.should_receive(:message).with(:chat?).and_yield(stanza)

    fj.should_receive(:on_disconnect).with(stanza).and_return(true)
    fjc.should_receive(:disconnected).and_yield(stanza)

    fj.start
  end

  it "joins a chat room after connecting" do
    ::Redis.should_receive(:new)

    fjc = mock(Flapjack::Gateways::Jabber::BotClient)
    fjc.should_receive(:write_to_stream).with(an_instance_of(Blather::Stanza::Presence))
    fjc.should_receive(:say).with(config['rooms'].first, an_instance_of(String), :groupchat)

    fj = Flapjack::Gateways::Jabber::Bot.new(:config => config, :logger => @logger)
    fj.instance_variable_set('@client', fjc)

    kat = mock(EventMachine::PeriodicTimer)
    EventMachine.should_receive(:add_periodic_timer).with(60).and_yield.and_return(kat)
    fjc.should_receive(:connected?).and_return(true)
    fjc.should_receive(:write).with(' ')

    fj.send(:on_ready, stanza)
  end

  it "receives an acknowledgement message" do
    stanza.should_receive(:body).and_return('flapjack: ACKID 876 fixing now duration: 90m')
    from = mock('from')
    from.should_receive(:stripped).and_return('sender')
    stanza.should_receive(:from).and_return(from)

    redis = mock('redis')
    redis.should_receive(:hget).with('unacknowledged_failures', '876').
      and_return('main-example.com:ping')
    Redis.should_receive(:new).and_return(redis)

    entity_check = mock(Flapjack::Data::EntityCheck)
    entity_check.should_receive(:in_unscheduled_maintenance?)
    entity_check.should_receive(:create_acknowledgement).
      with('summary' => 'fixing now', 'acknowledgement_id' => '876', 'duration' => (90 * 60))
    entity_check.should_receive(:entity_name).and_return('main-example.com')
    entity_check.should_receive(:check).and_return('ping')

    Flapjack::Data::EntityCheck.should_receive(:for_event_id).
      with('main-example.com:ping', :redis => redis).
      and_return(entity_check)

    fjc = mock(Flapjack::Gateways::Jabber::BotClient)
    fjc.should_receive(:say).with('sender', an_instance_of(String), :groupchat)

    fj = Flapjack::Gateways::Jabber::Bot.new(:config => config, :logger => @logger)
    fj.instance_variable_set('@connected', true)
    fj.instance_variable_set('@client', fjc)

    fj.send(:on_groupchat, stanza)
  end

  it "receives a message it doesn't understand" do
    ::Redis.should_receive(:new)

    stanza.should_receive(:body).once.and_return('flapjack: hello!')
    from = mock('from')
    from.should_receive(:stripped).and_return('sender')
    stanza.should_receive(:from).and_return(from)

    fjc = mock(Flapjack::Gateways::Jabber::BotClient)
    fjc.should_receive(:say).with('sender', an_instance_of(String), :groupchat)

    fj = Flapjack::Gateways::Jabber::Bot.new(:config => config, :logger => @logger)
    fj.instance_variable_set('@connected', true)
    fj.instance_variable_set('@client', fjc)

    fj.send(:on_groupchat, stanza)
  end

  it "reconnects when disconnected (if not quitting)" do
    ::Redis.should_receive(:new)

    kat = mock(EventMachine::PeriodicTimer)
    kat.should_receive(:cancel)

    fjc = mock(Flapjack::Gateways::Jabber::BotClient)
    fj = Flapjack::Gateways::Jabber::Bot.new(:config => config, :logger => @logger)
    fj.instance_variable_set('@client', fjc)
    fj.instance_variable_set('@keepalive_timer', kat)

    EM::Timer.should_receive(:new).with(5).and_yield
    fjc.should_receive(:run)

    ret = fj.send(:on_disconnect, stanza)
    ret.should be_true
  end

  it "prompts the blocking redis connection to quit" do
    redis = mock('redis')
    redis.should_receive(:rpush).with('jabber_notifications', %q{{"notification_type":"shutdown"}})

    ::Redis.should_receive(:new).twice.and_return(redis)
    fjn = Flapjack::Gateways::Jabber::Notifier.new(:config => config, :logger => @logger)

    fjn.stop
  end

  it "runs a blocking loop listening for notifications" do
    redis = mock('redis')
    ::Redis.should_receive(:new).and_return(redis)

    jb = mock(Flapjack::Gateways::Jabber::Bot)
    jb.should_receive(:announce).with(an_instance_of(String), "example@example.com")

    fjn = Flapjack::Gateways::Jabber::Notifier.new(:config => config, :logger => @logger,
            :siblings => [jb])

    blpop_count = 0

    redis.should_receive(:blpop).twice {
      blpop_count += 1
      if blpop_count == 1
        ["jabber_notifications", %q{{"notification_type":"problem","event_id":"main-example.com:ping","state":"critical","summary":"!!!","address":"example@example.com"}}]
      else
        fjn.instance_variable_set('@should_quit', true)
        ["jabber_notifications", %q{{"notification_type":"shutdown"}}]
      end
    }

    fjn.start
  end

end
