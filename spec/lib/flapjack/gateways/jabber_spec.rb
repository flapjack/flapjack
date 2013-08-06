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

    let(:redis) { mock(::Redis) }

    it "starts and is stopped from another thread"

    it "receives messages from another thread"

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

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger, :boot_time => now)
      fji.instance_variable_set('@siblings', [bot])
      fji.interpret('room1', 'jim', now.to_i + 60, 'identify')
    end

    it "interprets a received entity information command" # do
    #   bot.should_receive(:respond_to?).with(:announce).and_return(true)
    #   bot.should_receive(:announce).with('room1', '')

    #   Redis.should_receive(:new).and_return(redis)

    #   fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
    #   fji.instance_variable_set('@siblings', [bot])
    #   fji.interpret('room1', 'jim', now.to_i, '')
    # end

    it "interprets a received check information command" # do
    #   bot.should_receive(:respond_to?).with(:announce).and_return(true)
    #   bot.should_receive(:announce).with('room1', '')

    #   Redis.should_receive(:new).and_return(redis)

    #   fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
    #   fji.instance_variable_set('@siblings', [bot])
    #   fji.interpret('room1', 'jim', now.to_i, '')
    # end

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

    it "interprets a received check acknowledgement command" # do
    #   bot.should_receive(:respond_to?).with(:announce).and_return(true)
    #   bot.should_receive(:announce).with('room1', '')

    #   Redis.should_receive(:new).and_return(redis)

    #   fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
    #   fji.instance_variable_set('@siblings', [bot])
    #   fji.interpret('room1', 'jim', now.to_i, '')
    # end
 
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

    it "announces a message to a chat room"

    it "says a message to an individual user"

  end

end
