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

  let(:stanza) { double('stanza') }

  it "hooks up event handlers to the appropriate methods" do
    Socket.should_receive(:gethostname).and_return('thismachine')

    Flapjack::RedisPool.should_receive(:new)
    fj = Flapjack::Gateways::Jabber.new(:config => config, :logger => @logger)

    EventMachine::Synchrony.should_receive(:next_tick).exactly(4).times.and_yield

    fj.should_receive(:register_handler).with(:ready).and_yield(stanza)
    fj.should_receive(:on_ready).with(stanza)

    fj.should_receive(:register_handler).with(:message, :groupchat?, :body => /^flapjack:\s+/).and_yield(stanza)
    fj.should_receive(:on_groupchat).with(stanza)

    fj.should_receive(:register_handler).with(:message, :chat?).and_yield(stanza)
    fj.should_receive(:on_chat).with(stanza)

    fj.should_receive(:register_handler).with(:disconnected).and_yield(stanza)
    fj.should_receive(:on_disconnect).with(stanza).and_return(true)

    fj.setup
  end

  it "joins a chat room after connecting" do
    Flapjack::RedisPool.should_receive(:new)

    fj = Flapjack::Gateways::Jabber.new(:config => config, :logger => @logger)
    fj.should_receive(:connected?).and_return(true)

    EventMachine::Synchrony.should_receive(:next_tick).and_yield
    fj.should_receive(:write).with(an_instance_of(Blather::Stanza::Presence))
    fj.should_receive(:write).with(an_instance_of(Blather::Stanza::Message))

    fj.on_ready(stanza)
  end

  it "receives an acknowledgement message" do
    stanza.should_receive(:body).and_return('flapjack: ACKID 876 fixing now duration: 90m')
    from = double('from')
    from.should_receive(:stripped).and_return('sender')
    stanza.should_receive(:from).and_return(from)

    redis = double('redis')
    redis.should_receive(:hget).with('unacknowledged_failures', '876').
      and_return('main-example.com:ping')

    entity_check = double(Flapjack::Data::EntityCheck)
    entity_check.should_receive(:in_unscheduled_maintenance?)

    Flapjack::Data::Event.should_receive(:create_acknowledgement).
      with('main-example.com', 'ping', :summary => 'fixing now',
           :acknowledgement_id => '876',
           :duration => (90 * 60), :redis => redis)

    Flapjack::Data::EntityCheck.should_receive(:for_event_id).
      with('main-example.com:ping', :redis => redis).
      and_return(entity_check)

    Flapjack::RedisPool.should_receive(:new).and_return(redis)
    fj = Flapjack::Gateways::Jabber.new(:config => config, :logger => @logger)

    EventMachine::Synchrony.should_receive(:next_tick).and_yield
    fj.should_receive(:connected?).and_return(true)
    fj.should_receive(:write).with(an_instance_of(Blather::Stanza::Message))

    fj.on_groupchat(stanza)
  end

  it "strips XML tags from the received message" do
    stanza.should_receive(:body).
      and_return('flapjack: tell me about <span style="text-decoration: underline;">' +
                 '<a href="http://example.org/">example.org</a></span>')

    from = double('from')
    from.should_receive(:stripped).and_return('sender')
    stanza.should_receive(:from).and_return(from)

    redis = double('redis')
    entity = double(Flapjack::Data::Entity)
    entity.should_receive(:check_list).and_return(['ping'])

    Flapjack::Data::Entity.should_receive(:find_by_name).with('example.org',
      :redis => redis).and_return(entity)

    entity_check = double(Flapjack::Data::EntityCheck)
    entity_check.should_receive(:current_maintenance).with(:scheduled => true).and_return(nil)
    entity_check.should_receive(:current_maintenance).with(:unscheduled => true).and_return(nil)

    Flapjack::Data::EntityCheck.should_receive(:for_entity).with(entity, 'ping',
      :redis => redis).and_return(entity_check)

    Flapjack::RedisPool.should_receive(:new).and_return(redis)
    fj = Flapjack::Gateways::Jabber.new(:config => config, :logger => @logger)

    EventMachine::Synchrony.should_receive(:next_tick).and_yield
    fj.should_receive(:connected?).and_return(true)
    fj.should_receive(:write).with(an_instance_of(Blather::Stanza::Message))

    fj.on_groupchat(stanza)
  end

  it "receives a message it doesn't understand" do
    stanza.should_receive(:body).once.and_return('flapjack: hello!')
    from = double('from')
    from.should_receive(:stripped).and_return('sender')
    stanza.should_receive(:from).and_return(from)

    Flapjack::RedisPool.should_receive(:new)
    fj = Flapjack::Gateways::Jabber.new(:config => config, :logger => @logger)

    EventMachine::Synchrony.should_receive(:next_tick).and_yield
    fj.should_receive(:connected?).and_return(true)
    fj.should_receive(:write).with(an_instance_of(Blather::Stanza::Message))

    fj.on_groupchat(stanza)
  end

  it "reconnects when disconnected (if not quitting)" do
    Flapjack::RedisPool.should_receive(:new)
    fj = Flapjack::Gateways::Jabber.new(:config => config, :logger => @logger)

    attempts = 0

    EventMachine::Synchrony.should_receive(:sleep).with(5).exactly(1).times
    EventMachine::Synchrony.should_receive(:sleep).with(2).exactly(3).times
    fj.should_receive(:connect).exactly(4).times.and_return {
      attempts +=1
      raise StandardError.new unless attempts > 3
    }

    ret = fj.on_disconnect(stanza)
    ret.should be_true
  end

  it "prompts the blocking redis connection to quit" do
    shutdown_redis = double('shutdown_redis')
    shutdown_redis.should_receive(:rpush).with('jabber_notifications', %q{{"notification_type":"shutdown"}})
    EM::Hiredis.should_receive(:connect).and_return(shutdown_redis)

    redis = double('redis')
    Flapjack::RedisPool.should_receive(:new).and_return(redis)
    fj = Flapjack::Gateways::Jabber.new(:config => config, :logger => @logger)

    fj.stop
  end

  it "runs a blocking loop listening for notifications" do
    timer = double('timer')
    timer.should_receive(:cancel)
    EM::Synchrony.should_receive(:add_periodic_timer).with(1).and_return(timer)

    redis = double('redis')

    Flapjack::RedisPool.should_receive(:new).and_return(redis)
    fj = Flapjack::Gateways::Jabber.new(:config => config, :logger => @logger)
    fj.should_receive(:register_handler).exactly(4).times

    fj.should_receive(:connect)
    fj.should_receive(:connected?).exactly(3).times.and_return(true)

    blpop_count = 0

    event_json = '{"notification_type":"problem","event_id":"main-example.com:ping",' +
      '"state":"critical","summary":"!!!","duration":43,"state_duration":76}'
    redis.should_receive(:blpop).twice {
      blpop_count += 1
      if blpop_count == 1
        ["jabber_notifications", event_json]
      else
        fj.instance_variable_set('@should_quit', true)
        ["jabber_notifications", %q{{"notification_type":"shutdown"}}]
      end
    }

    EventMachine::Synchrony.should_receive(:next_tick).twice.and_yield
    fj.should_receive(:write).with(an_instance_of(Blather::Stanza::Message))
    fj.should_receive(:close)

    fj.start
  end

end
