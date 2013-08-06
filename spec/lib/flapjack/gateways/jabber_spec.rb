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

  let(:now) { Time.now}

  context 'notifications' do

    let(:bot) { mock(Flapjack::Gateways::Jabber::Bot) }

    it "starts and is stopped from another thread"

    it "handles notifications received via Redis" do
      bot.should_receive(:respond_to?).with(:announce).and_return(true)
      bot.should_receive(:announce) # TODO with()

      message = {'notification_type'  => 'problem',
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

      fjn = Flapjack::Gateways::Jabber::Notifier.new(:config => config, :logger => @logger)
      fjn.instance_variable_set('@siblings', [bot])
      fjn.send(:handle_message, message)
    end

  end

  context 'commands' do

    let(:bot) { mock(Flapjack::Gateways::Jabber::Bot) }

    let(:entity) { mock(Flapjack::Data::Entity) }
    let(:entity_check) { mock(Flapjack::Data::EntityCheck) }

    let(:redis) { mock(::Redis) }

    it "starts and is stopped from another thread"

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

    it "starts and is stopped from another thread"

    it "announces a message to a chat room" do
      muc_client = mock(::Jabber::MUC::SimpleMUCClient)
      muc_client.should_receive(:say).with('hello!')

      fjb = Flapjack::Gateways::Jabber::Bot.new(:config => config, :logger => @logger)
      fjb.instance_variable_set('@muc_clients', {'room1' => muc_client})
      fjb.announce('room1', 'hello!')
    end

    it "says a message to an individual user" do
      message = mock(::Jabber::Message)
      ::Jabber::Message.should_receive(:new).
        with('jim', 'hello!').and_return(message)

      client = mock(::Jabber::Client)
      client.should_receive(:send).with(message)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:config => config, :logger => @logger)
      fjb.instance_variable_set('@client', client)
      fjb.say('jim', 'hello!')
    end

  end

end
