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

  let(:redis) { mock(::Redis) }

  let(:now) { Time.now}

  context 'notifications' do

    let(:message) { {'notification_type'  => 'problem',
                     'contact_first_name' => 'John',
                     'contact_last_name' => 'Smith',
                     'address' => 'johns@example.com',
                     'state' => 'CRITICAL',
                     'summary' => '',
                     'last_state' => 'OK',
                     'last_summary' => 'TEST',
                     'details' => 'Testing',
                     'time' => now.to_i,
                     'event_id' => 'app-02:ping'} 
                  }

    # TODO use separate threads in the test instead?
    it "starts and is stopped by an exception" do
      Redis.should_receive(:new).and_return(redis)

      fjn = Flapjack::Gateways::Jabber::Notifier.new(:config => config, :logger => @logger)      
      fjn.should_receive(:handle_message).with(message)

      Flapjack::Data::Message.should_receive(:foreach_on_queue).
        with('jabber_notifications', :redis => redis).and_yield(message)

      Flapjack::Data::Message.should_receive(:wait_for_queue).
        with('jabber_notifications', :redis => redis).and_raise(Flapjack::PikeletStop)

      fjn.start
    end

    it "handles notifications received via Redis" do
      bot = mock(Flapjack::Gateways::Jabber::Bot)
      bot.should_receive(:respond_to?).with(:announce).and_return(true)
      bot.should_receive(:announce).with('johns@example.com', /PROBLEM ::/)

      fjn = Flapjack::Gateways::Jabber::Notifier.new(:config => config, :logger => @logger)
      fjn.instance_variable_set('@siblings', [bot])
      fjn.send(:handle_message, message)
    end

  end

  context 'commands' do

    let(:bot) { mock(Flapjack::Gateways::Jabber::Bot) }

    let(:entity) { mock(Flapjack::Data::Entity) }
    let(:entity_check) { mock(Flapjack::Data::EntityCheck) }

    # TODO use separate threads in the test instead?
    it "starts and is stopped by a signal" do
      Redis.should_receive(:new).and_return(redis)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      msg = {:room => 'room1', :nick => 'jim', :time => now.to_i, :message => 'help'}
      fji.instance_variable_get('@messages').push(msg)
      fji.instance_variable_get('@message_cond').should_receive(:wait_while).and_return {
        fji.instance_variable_set('@should_quit', true)
      }
      fji.should_receive(:interpret).with('room1', 'jim', now.to_i, 'help')

      fji.start
    end

    it "receives a message and and signals a condition variable" do
      Redis.should_receive(:new).and_return(redis)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_get('@messages').should be_empty
      fji.instance_variable_get('@message_cond').should_receive(:signal)

      fji.receive_message('room1', 'jim', now.to_i, 'help')
      fji.instance_variable_get('@messages').should have(1).message
    end

    it "interprets a received help command (from a room)" do
      bot.should_receive(:respond_to?).with(:announce).and_return(true)
      bot.should_receive(:announce).with('room1', /^commands:/)

      Redis.should_receive(:new).and_return(redis)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@siblings', [bot])
      fji.interpret('room1', 'jim', now.to_i, 'help')
    end

    it "interprets a received help command (from a user)" do
      bot.should_receive(:respond_to?).with(:announce).and_return(true)
      bot.should_receive(:say).with('jim', /^commands:/)

      Redis.should_receive(:new).and_return(redis)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@siblings', [bot])
      fji.interpret(nil, 'jim', now.to_i, 'help')
    end

    it "interprets a received identify command " do
      bot.should_receive(:respond_to?).with(:announce).and_return(true)
      bot.should_receive(:announce).with('room1', /System CPU Time/)

      Redis.should_receive(:new).and_return(redis)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config,
              :logger => @logger, :boot_time => now)
      fji.instance_variable_set('@siblings', [bot])
      fji.interpret('room1', 'jim', now.to_i + 60, 'identify')
    end

    it "interprets a received entity information command" do
      bot.should_receive(:respond_to?).with(:announce).and_return(true)
      bot.should_receive(:announce).with('room1', /Not in scheduled or unscheduled maintenance./)

      Redis.should_receive(:new).and_return(redis)

      entity.should_receive(:check_list).and_return(['ping'])
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with('example.com', :redis => redis).and_return(entity)

      entity_check.should_receive(:check).and_return('ping')
      entity_check.should_receive(:current_maintenance).
        with(:scheduled => true).and_return(nil)
      entity_check.should_receive(:current_maintenance).
        with(:unscheduled => true).and_return(nil)

      Flapjack::Data::EntityCheck.should_receive(:for_entity).
        with(entity, 'ping', :redis => redis).and_return(entity_check)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@siblings', [bot])
      fji.interpret('room1', 'jim', now.to_i, 'tell me about example.com')
    end

    it "interprets a received check information command" do
      bot.should_receive(:respond_to?).with(:announce).and_return(true)
      bot.should_receive(:announce).with('room1', /Not in scheduled or unscheduled maintenance./)

      Redis.should_receive(:new).and_return(redis)

      Flapjack::Data::Entity.should_receive(:find_by_name).
        with('example.com', :redis => redis).and_return(entity)

      entity_check.should_receive(:current_maintenance).
        with(:scheduled => true).and_return(nil)
      entity_check.should_receive(:current_maintenance).
        with(:unscheduled => true).and_return(nil)

      Flapjack::Data::EntityCheck.should_receive(:for_entity).
        with(entity, 'ping', :redis => redis).and_return(entity_check)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@siblings', [bot])
      fji.interpret('room1', 'jim', now.to_i, 'tell me about example.com:ping')
    end

    it "interprets a received entity search command" do
      bot.should_receive(:respond_to?).with(:announce).and_return(true)
      bot.should_receive(:announce).with('room1', "found 1 entity matching /example/ ... \nexample.com")

      Redis.should_receive(:new).and_return(redis)

      Flapjack::Data::Entity.should_receive(:find_all_name_matching).
        with("example", :redis => redis).and_return(['example.com'])

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@siblings', [bot])
      fji.interpret('room1', 'jim', now.to_i, 'find entities matching /example/')
    end

    it "interprets a received entity search command (with an invalid pattern)" do
      bot.should_receive(:respond_to?).with(:announce).and_return(true)
      bot.should_receive(:announce).with('room1', 'that doesn\'t seem to be a valid pattern - /(example/')

      Redis.should_receive(:new).and_return(redis)

      Flapjack::Data::Entity.should_receive(:find_all_name_matching).
        with("(example", :redis => redis).and_return(nil)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@siblings', [bot])
      fji.interpret('room1', 'jim', now.to_i, 'find entities matching /(example/')
    end

    it "interprets a received check acknowledgement command" do
      bot.should_receive(:respond_to?).with(:announce).and_return(true)
      bot.should_receive(:announce).with('room1', 'ACKing ping on example.com (1234)')

      Flapjack::Data::Event.should_receive(:create_acknowledgement).
        with('events', 'example.com', 'ping',
             :summary => 'JJ looking', :acknowledgement_id => '1234',
             :duration => (60 * 60), :redis => redis)

      redis.should_receive(:hget).with('unacknowledged_failures', '1234').and_return('example.com:ping')
      Redis.should_receive(:new).and_return(redis)

      entity_check.should_receive(:in_unscheduled_maintenance?).and_return(false)
      Flapjack::Data::EntityCheck.should_receive(:for_event_id).
        with('example.com:ping', :redis => redis).and_return(entity_check)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@siblings', [bot])
      fji.interpret('room1', 'jim', now.to_i, 'ACKID 1234 JJ looking duration: 1 hour')
    end
 
    it "interprets a received check notification test command" do
      bot.should_receive(:respond_to?).with(:announce).and_return(true)
      bot.should_receive(:announce).with('room1', /so you want me to test notifications/)

      Redis.should_receive(:new).and_return(redis)

      Flapjack::Data::Entity.should_receive(:find_by_name).with('example.com', :redis => redis).and_return(entity)

      Flapjack::Data::Event.should_receive(:test_notifications).with('events', 'example.com', 'ping',
        :summary => an_instance_of(String), :redis => redis)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@siblings', [bot])
      fji.interpret('room1', 'jim', now.to_i, 'test notifications for example.com:ping')
    end

    it "interprets a received check notification test command (for a missing entity)" do
      bot.should_receive(:respond_to?).with(:announce).and_return(true)
      bot.should_receive(:announce).with('room1', "yeah, no I can't see example.com in my systems")

      Redis.should_receive(:new).and_return(redis)

      Flapjack::Data::Entity.should_receive(:find_by_name).with('example.com', :redis => redis).and_return(nil)
      Flapjack::Data::Event.should_not_receive(:test_notifications)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@siblings', [bot])
      fji.interpret('room1', 'jim', now.to_i, 'test notifications for example.com:ping')
    end

    it "doesn't interpret an unmatched command" do
      bot.should_receive(:respond_to?).with(:announce).and_return(true)
      bot.should_receive(:announce).with('room1', /^what do you mean/)

      Redis.should_receive(:new).and_return(redis)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@siblings', [bot])
      fji.interpret('room1', 'jim', now.to_i, 'hello!')
    end

  end

  context 'XMPP' do

    let(:client)     { mock(::Jabber::Client) }
    let(:muc_client) { mock(::Jabber::MUC::SimpleMUCClient) }

    # TODO use separate threads in the test instead?
    it "starts and is stopped by a signal" do
      Redis.should_receive(:new).and_return(redis)

      interpreter = mock(Flapjack::Gateways::Jabber::Interpreter)
      interpreter.should_receive(:respond_to?).with(:interpret).and_return(true)
      interpreter.should_receive(:receive_message).with(nil, 'jim', nil, 'hello!')
      interpreter.should_receive(:receive_message).
        with('flapjacktest@conference.example.com', 'jim', now.to_i, 'hello!')

      client.should_receive(:connect)
      client.should_receive(:auth).with('password')
      client.should_receive(:send).with(an_instance_of(::Jabber::Presence))

      msg_client = mock('msg_client')
      msg_client.should_receive(:body).and_return('hello!')
      msg_client.should_receive(:from).and_return('jim')
      msg_client.should_receive(:each_element).and_yield([]) # TODO improve

      client.should_receive(:add_message_callback).and_yield(msg_client)

      muc_client.should_receive(:on_message).and_yield(now.to_i, 'jim', 'flapjack: hello!')
      muc_client.should_receive(:join).with('flapjacktest@conference.example.com/flapjack')
      muc_client.should_receive(:say).with(/^flapjack jabber gateway started/)

      muc_client.should_receive(:active?).and_return(true)
      muc_client.should_receive(:exit)

      client.should_receive(:close)

      ::Jabber::Client.should_receive(:new).and_return(client)
      ::Jabber::MUC::SimpleMUCClient.should_receive(:new).and_return(muc_client)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:config => config, :logger => @logger)
      fjb.instance_variable_set('@siblings', [interpreter])
      fjb.instance_variable_get('@shutdown_cond').should_receive(:wait_until)
      fjb.start
    end

    it "announces a message to a chat room" do
      muc_client.should_receive(:say).with('hello!')

      fjb = Flapjack::Gateways::Jabber::Bot.new(:config => config, :logger => @logger)
      fjb.instance_variable_set('@muc_clients', {'room1' => muc_client})
      fjb.announce('room1', 'hello!')
    end

    it "says a message to an individual user" do
      message = mock(::Jabber::Message)
      ::Jabber::Message.should_receive(:new).
        with('jim', 'hello!').and_return(message)

      client.should_receive(:send).with(message)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:config => config, :logger => @logger)
      fjb.instance_variable_set('@client', client)
      fjb.say('jim', 'hello!')
    end

  end

end
