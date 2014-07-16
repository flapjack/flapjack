require 'spec_helper'
require 'flapjack/gateways/jabber'

describe Flapjack::Gateways::Jabber, :logger => true do

  let(:config) { {'queue'       => 'jabber_notifications',
                  'server'      => 'example.com',
                  'port'        => '5222',
                  'jabberid'    => 'flapjack@example.com',
                  'password'    => 'password',
                  'alias'       => 'flapjack',
                  'identifiers' => ['@flapjack'],
                  'rooms'       => ['flapjacktest@conference.example.com']
                 }
  }

  let(:stanza) { double('stanza') }

  it "hooks up event handlers to the appropriate methods" do
    expect(Socket).to receive(:gethostname).and_return('thismachine')

    expect(Flapjack::RedisPool).to receive(:new)
    fj = Flapjack::Gateways::Jabber.new(:config => config, :logger => @logger)

    expect(EventMachine::Synchrony).to receive(:next_tick).exactly(4).times.and_yield

    expect(fj).to receive(:register_handler).with(:ready).and_yield(stanza)
    expect(fj).to receive(:on_ready).with(stanza)

    body_matchers = [{:body => /^@flapjack[:\s]/}, {:body => /^flapjack[:\s]/}]
    expect(fj).to receive(:register_handler).with(:message, :groupchat?, body_matchers).and_yield(stanza)
    expect(fj).to receive(:on_groupchat).with(stanza)

    expect(fj).to receive(:register_handler).with(:message, :chat?, :body).and_yield(stanza)
    expect(fj).to receive(:on_chat).with(stanza)

    expect(fj).to receive(:register_handler).with(:disconnected).and_yield(stanza)
    expect(fj).to receive(:on_disconnect).with(stanza).and_return(true)

    fj.setup
  end

  it "joins a chat room after connecting" do
    expect(Flapjack::RedisPool).to receive(:new)

    fj = Flapjack::Gateways::Jabber.new(:config => config, :logger => @logger)
    expect(fj).to receive(:connected?).and_return(true)

    expect(EventMachine::Synchrony).to receive(:next_tick).and_yield
    expect(fj).to receive(:write).with(an_instance_of(Blather::Stanza::Presence))
    expect(fj).to receive(:write).with(an_instance_of(Blather::Stanza::Message))

    fj.on_ready(stanza)
  end

  it "receives an acknowledgement message" do
    expect(stanza).to receive(:body).twice.and_return('flapjack: ACKID 1f8ac10f fixing now duration: 90m')
    from = double('from')
    #expect(from).to receive(:resource).and_return('sender')
    expect(from).to receive(:stripped).and_return('sender')
    expect(stanza).to receive(:from).and_return(from)

    #identifiers = double('identifiers')
    #expect(identifiers).to receive

    redis = double('redis')
    expect(redis).to receive(:hget).with('checks_by_hash', '1f8ac10f').
      and_return('main-example.com:ping')

    entity_check = double(Flapjack::Data::EntityCheck)
    expect(entity_check).to receive(:in_unscheduled_maintenance?)

    expect(Flapjack::Data::Event).to receive(:create_acknowledgement).
      with('main-example.com', 'ping', :summary => 'fixing now',
           :acknowledgement_id => '1f8ac10f',
           :duration => (90 * 60), :redis => redis)

    expect(Flapjack::Data::EntityCheck).to receive(:for_event_id).
      with('main-example.com:ping', :redis => redis).
      and_return(entity_check)

    expect(Flapjack::RedisPool).to receive(:new).and_return(redis)
    fj = Flapjack::Gateways::Jabber.new(:config => config, :logger => @logger)

    expect(EventMachine::Synchrony).to receive(:next_tick).and_yield
    expect(fj).to receive(:connected?).and_return(true)
    expect(fj).to receive(:write).with(an_instance_of(Blather::Stanza::Message))

    fj.on_groupchat(stanza)
  end

  it "strips XML tags from the received message" do
    expect(stanza).to receive(:body).twice.
      and_return('flapjack: tell me about <span style="text-decoration: underline;">' +
                 '<a href="http://example.org/">example.org</a></span>')

    from = double('from')
    expect(from).to receive(:stripped).and_return('sender')
    expect(stanza).to receive(:from).and_return(from)

    redis = double('redis')
    entity = double(Flapjack::Data::Entity)
    expect(entity).to receive(:check_list).and_return(['ping'])

    expect(Flapjack::Data::Entity).to receive(:find_by_name).with('example.org',
      :redis => redis).and_return(entity)

    entity_check = double(Flapjack::Data::EntityCheck)
    expect(entity_check).to receive(:current_maintenance).with(:scheduled => true).and_return(nil)
    expect(entity_check).to receive(:current_maintenance).with(:unscheduled => true).and_return(nil)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity).with(entity, 'ping',
      :redis => redis).and_return(entity_check)

    expect(Flapjack::RedisPool).to receive(:new).and_return(redis)
    fj = Flapjack::Gateways::Jabber.new(:config => config, :logger => @logger)

    expect(EventMachine::Synchrony).to receive(:next_tick).and_yield
    expect(fj).to receive(:connected?).and_return(true)
    expect(fj).to receive(:write).with(an_instance_of(Blather::Stanza::Message))

    fj.on_groupchat(stanza)
  end

  it "handles a message with a newline in it" do
    expect(stanza).to receive(:body).twice.
      and_return("flapjack: tell me about \nexample.com")

    from = double('from')
    expect(from).to receive(:stripped).and_return('sender')
    expect(stanza).to receive(:from).and_return(from)

    redis = double('redis')
    entity = double(Flapjack::Data::Entity)
    expect(entity).to receive(:check_list).and_return(['ping'])

    expect(Flapjack::Data::Entity).to receive(:find_by_name).with('example.com',
      :redis => redis).and_return(entity)

    entity_check = double(Flapjack::Data::EntityCheck)
    expect(entity_check).to receive(:current_maintenance).with(:scheduled => true).and_return(nil)
    expect(entity_check).to receive(:current_maintenance).with(:unscheduled => true).and_return(nil)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity).with(entity, 'ping',
      :redis => redis).and_return(entity_check)

    expect(Flapjack::RedisPool).to receive(:new).and_return(redis)
    fj = Flapjack::Gateways::Jabber.new(:config => config, :logger => @logger)

    expect(EventMachine::Synchrony).to receive(:next_tick).and_yield
    expect(fj).to receive(:connected?).and_return(true)
    expect(fj).to receive(:write).with(an_instance_of(Blather::Stanza::Message))

    fj.on_groupchat(stanza)
  end

  it "receives a message it doesn't understand" do
    expect(stanza).to receive(:body).twice.and_return('flapjack: hello!')
    from = double('from')
    expect(from).to receive(:stripped).and_return('sender')
    expect(stanza).to receive(:from).and_return(from)

    expect(Flapjack::RedisPool).to receive(:new)
    fj = Flapjack::Gateways::Jabber.new(:config => config, :logger => @logger)

    expect(EventMachine::Synchrony).to receive(:next_tick).and_yield
    expect(fj).to receive(:connected?).and_return(true)
    expect(fj).to receive(:write).with(an_instance_of(Blather::Stanza::Message))

    fj.on_groupchat(stanza)
  end

  it "reconnects when disconnected (if not quitting)" do
    expect(Flapjack::RedisPool).to receive(:new)
    fj = Flapjack::Gateways::Jabber.new(:config => config, :logger => @logger)

    attempts = 0

    expect(EventMachine::Synchrony).to receive(:sleep).with(5).exactly(1).times
    expect(EventMachine::Synchrony).to receive(:sleep).with(2).exactly(3).times
    expect(fj).to receive(:connect).exactly(4).times.and_return {
      attempts +=1
      raise StandardError.new unless attempts > 3
    }

    ret = fj.on_disconnect(stanza)
    expect(ret).to be true
  end

  it "prompts the blocking redis connection to quit" do
    shutdown_redis = double('shutdown_redis')
    expect(shutdown_redis).to receive(:rpush).with('jabber_notifications', %q{{"notification_type":"shutdown"}})
    expect(EM::Hiredis).to receive(:connect).and_return(shutdown_redis)

    redis = double('redis')
    expect(Flapjack::RedisPool).to receive(:new).and_return(redis)
    fj = Flapjack::Gateways::Jabber.new(:config => config, :logger => @logger)

    fj.stop
  end

  it "runs a blocking loop listening for notifications" do
    timer = double('timer')
    expect(timer).to receive(:cancel)
    expect(EM::Synchrony).to receive(:add_periodic_timer).with(1).and_return(timer)

    redis = double('redis')

    expect(Flapjack::RedisPool).to receive(:new).and_return(redis)
    fj = Flapjack::Gateways::Jabber.new(:config => config, :logger => @logger)
    expect(fj).to receive(:register_handler).exactly(4).times

    expect(fj).to receive(:connect)
    expect(fj).to receive(:connected?).exactly(3).times.and_return(true)

    blpop_count = 0

    event_json = '{"notification_type":"problem","event_id":"main-example.com:ping",' +
      '"state":"critical","summary":"!!!","duration":43,"state_duration":76}'
    expect(redis).to receive(:blpop).twice {
      blpop_count += 1
      if blpop_count == 1
        ["jabber_notifications", event_json]
      else
        fj.instance_variable_set('@should_quit', true)
        ["jabber_notifications", %q{{"notification_type":"shutdown"}}]
      end
    }

    expect(EventMachine::Synchrony).to receive(:next_tick).twice.and_yield
    expect(fj).to receive(:write).with(an_instance_of(Blather::Stanza::Message))
    expect(fj).to receive(:close)

    fj.start

    expect(@logger.errors).to be_empty
  end

end
