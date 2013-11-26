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

  let(:redis) { double(::Redis) }
  let(:stanza) { double('stanza') }

  let(:now) { Time.now}

  let(:lock) { double(Monitor) }
  let(:stop_cond) { double(MonitorMixin::ConditionVariable) }

  before(:each) do
    Flapjack.stub(:redis).and_return(redis)
  end

  context 'notifications' do

    let(:queue) { double(Flapjack::RecordQueue) }

    let(:alert) { double(Flapjack::Data::Alert) }

    it "starts and is stopped by an exception" do
      Flapjack::RecordQueue.should_receive(:new).with('jabber_notifications',
        Flapjack::Data::Alert).and_return(queue)

      lock.should_receive(:synchronize).and_yield
      queue.should_receive(:foreach).and_yield(alert)
      queue.should_receive(:wait).and_raise(Flapjack::PikeletStop)

      redis.should_receive(:quit)

      fjn = Flapjack::Gateways::Jabber::Notifier.new(:lock => lock,
        :config => config, :logger => @logger)
      fjn.should_receive(:handle_alert).with(alert)

      expect { fjn.start }.to raise_error(Flapjack::PikeletStop)
    end

    it "handles notifications received via Redis" do
      bot = double(Flapjack::Gateways::Jabber::Bot)
      bot.should_receive(:respond_to?).with(:announce).and_return(true)
      bot.should_receive(:announce).with('johns@example.com', /Problem: /)

      check = double(Flapjack::Data::Check)
      check.should_receive(:entity_name).twice.and_return('app-02')
      check.should_receive(:name).twice.and_return('ping')

      alert.should_receive(:address).and_return('johns@example.com')
      alert.should_receive(:check).twice.and_return(check)
      alert.should_receive(:state).and_return('critical')
      alert.should_receive(:state_title_case).and_return('Critical')
      alert.should_receive(:summary).twice.and_return('')
      alert.should_receive(:event_count).and_return(33)
      alert.should_receive(:type).twice.and_return('problem')
      alert.should_receive(:type_sentence_case).and_return('Problem')
      alert.should_receive(:rollup).and_return(nil)

      fjn = Flapjack::Gateways::Jabber::Notifier.new(:config => config, :logger => @logger)
      fjn.instance_variable_set('@siblings', [bot])
      fjn.send(:handle_alert, alert)
    end

  end

  context 'commands' do

    let(:bot) { double(Flapjack::Gateways::Jabber::Bot) }

    let(:entity) { double(Flapjack::Data::Entity) }
    let(:entity_check) { double(Flapjack::Data::Check) }

    # TODO use separate threads in the test instead?
    it "starts and is stopped by a signal" do
      lock.should_receive(:synchronize).and_yield

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:lock => lock, :stop_condition => stop_cond,
        :config => config, :logger => @logger)
      msg = {:room => 'room1', :nick => 'jim', :time => now.to_i, :message => 'help'}
      fji.instance_variable_get('@messages').push(msg)
      stop_cond.should_receive(:wait_while).and_return {
        fji.instance_variable_set('@should_quit', true)
      }

      fji.should_receive(:interpret).with('room1', 'jim', now.to_i, 'help')

      redis.should_receive(:quit)
      fji.start
    end

    it "receives a message and and signals a condition variable" do
      lock.should_receive(:synchronize).and_yield

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:lock => lock, :stop_condition => stop_cond,
        :config => config, :logger => @logger)
      fji.instance_variable_get('@messages').should be_empty
      stop_cond.should_receive(:signal)

      fji.receive_message('room1', 'jim', now.to_i, 'help')
      fji.instance_variable_get('@messages').should have(1).message
    end

    it "interprets a received help command (from a room)" do
      bot.should_receive(:respond_to?).with(:announce).and_return(true)
      bot.should_receive(:announce).with('room1', /^commands:/)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@siblings', [bot])
      fji.interpret('room1', 'jim', now.to_i, 'help')
    end

    it "interprets a received help command (from a user)" do
      bot.should_receive(:respond_to?).with(:announce).and_return(true)
      bot.should_receive(:say).with('jim', /^commands:/)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@siblings', [bot])
      fji.interpret(nil, 'jim', now.to_i, 'help')
    end

    it "interprets a received identify command " do
      bot.should_receive(:respond_to?).with(:announce).and_return(true)
      bot.should_receive(:announce).with('room1', /System CPU Time/)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config,
              :logger => @logger, :boot_time => now)
      fji.instance_variable_set('@siblings', [bot])
      fji.interpret('room1', 'jim', now.to_i + 60, 'identify')
    end

    it "interprets a received entity information command" do
      bot.should_receive(:respond_to?).with(:announce).and_return(true)
      bot.should_receive(:announce).with('room1', /Not in scheduled or unscheduled maintenance./)

      all_checks = double('all_checks', :all => [entity_check])
      entity.should_receive(:checks).and_return(all_checks)
      all_entities = double('all_entities', :all => [entity])
      Flapjack::Data::Entity.should_receive(:intersect).
        with(:name => 'example.com').and_return(all_entities)

      entity_check.should_receive(:name).twice.and_return('ping')
      entity_check.should_receive(:scheduled_maintenance_at).and_return(nil)
      entity_check.should_receive(:unscheduled_maintenance_at).and_return(nil)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@siblings', [bot])
      fji.interpret('room1', 'jim', now.to_i, 'tell me about example.com')
    end

    it "handles a message with a newline in it" do
      bot.should_receive(:respond_to?).with(:announce).and_return(true)
      bot.should_receive(:announce).with('room1', /Not in scheduled or unscheduled maintenance./)

      all_checks = double('all_checks', :all => [entity_check])
      entity.should_receive(:checks).and_return(all_checks)
      all_entities = double('all_entities', :all => [entity])
      Flapjack::Data::Entity.should_receive(:intersect).
        with(:name => 'example.com').and_return(all_entities)

      entity_check.should_receive(:name).twice.and_return('ping')
      entity_check.should_receive(:scheduled_maintenance_at).and_return(nil)
      entity_check.should_receive(:unscheduled_maintenance_at).and_return(nil)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@siblings', [bot])
      fji.interpret('room1', 'jim', now.to_i, "tell me \nabout example.com")
    end

    it "interprets a received check information command" do
      bot.should_receive(:respond_to?).with(:announce).and_return(true)
      bot.should_receive(:announce).with('room1', /Not in scheduled or unscheduled maintenance./)

      entity_check.should_receive(:scheduled_maintenance_at).and_return(nil)
      entity_check.should_receive(:unscheduled_maintenance_at).and_return(nil)

      all_checks = double('all_checks', :all => [entity_check])
      Flapjack::Data::Check.should_receive(:intersect).
        with(:entity_name => 'example.com', :name => 'ping').and_return(all_checks)

      all_entities = double('all_entities', :all => [entity])
      Flapjack::Data::Entity.should_receive(:intersect).
        with(:name => 'example.com').and_return(all_entities)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@siblings', [bot])
      fji.interpret('room1', 'jim', now.to_i, 'tell me about example.com:ping')
    end

    it "interprets a received entity search command" do
      bot.should_receive(:respond_to?).with(:announce).and_return(true)
      bot.should_receive(:announce).with('room1', "found 1 entity matching /example/ ... \nexample.com")

      Flapjack::Data::Entity.should_receive(:find_all_name_matching).
        with("example").and_return(['example.com'])

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@siblings', [bot])
      fji.interpret('room1', 'jim', now.to_i, 'find entities matching /example/')
    end

    it "interprets a received entity search command (with an invalid pattern)" do
      bot.should_receive(:respond_to?).with(:announce).and_return(true)
      bot.should_receive(:announce).with('room1', 'that doesn\'t seem to be a valid pattern - /(example/')

      Flapjack::Data::Entity.should_receive(:find_all_name_matching).
        with("(example").and_return(nil)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@siblings', [bot])
      fji.interpret('room1', 'jim', now.to_i, 'find entities matching /(example/')
    end

    it "interprets a received check acknowledgement command" do
      bot.should_receive(:respond_to?).with(:announce).and_return(true)
      bot.should_receive(:announce).with('room1', 'ACKing ping on example.com (1234)')

      entity_check.should_receive(:entity_name).and_return('example.com')
      entity_check.should_receive(:name).and_return('ping')
      entity_check.should_receive(:in_unscheduled_maintenance?).and_return(false)

      state = double(Flapjack::Data::CheckState)
      state.should_receive(:entity_check).and_return(entity_check)

      all_states = double('all_states', :all => [state])
      Flapjack::Data::CheckState.should_receive(:intersect).
        with(:count => '1234').and_return(all_states)

      Flapjack::Data::Event.should_receive(:create_acknowledgement).
        with('events', 'example.com', 'ping',
             :summary => 'JJ looking', :acknowledgement_id => '1234',
             :duration => (60 * 60))

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@siblings', [bot])
      fji.interpret('room1', 'jim', now.to_i, 'ACKID 1234 JJ looking duration: 1 hour')
    end

    it "interprets a received check notification test command" do
      bot.should_receive(:respond_to?).with(:announce).and_return(true)
      bot.should_receive(:announce).with('room1', /so you want me to test notifications/)

      all_entities = double('all_entities', :all => [entity])
      Flapjack::Data::Entity.should_receive(:intersect).
        with(:name => 'example.com').and_return(all_entities)

      Flapjack::Data::Event.should_receive(:test_notifications).with('events', 'example.com', 'ping',
        :summary => an_instance_of(String))

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@siblings', [bot])
      fji.interpret('room1', 'jim', now.to_i, 'test notifications for example.com:ping')
    end

    it "interprets a received check notification test command (for a missing entity)" do
      bot.should_receive(:respond_to?).with(:announce).and_return(true)
      bot.should_receive(:announce).with('room1', "yeah, no I can't see example.com in my systems")

      no_entities = double('no_entities', :all => [])
      Flapjack::Data::Entity.should_receive(:intersect).
        with(:name => 'example.com').and_return(no_entities)

      Flapjack::Data::Event.should_not_receive(:test_notifications)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@siblings', [bot])
      fji.interpret('room1', 'jim', now.to_i, 'test notifications for example.com:ping')
    end

    it "doesn't interpret an unmatched command" do
      bot.should_receive(:respond_to?).with(:announce).and_return(true)
      bot.should_receive(:announce).with('room1', /^what do you mean/)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@siblings', [bot])
      fji.interpret('room1', 'jim', now.to_i, 'hello!')
    end

  end

  context 'XMPP' do

    let(:client)      { double(::Jabber::Client) }
    let(:muc_client)  { double(::Jabber::MUC::SimpleMUCClient) }
    let(:muc_clients) { {config['rooms'].first => muc_client} }

    # TODO use separate threads in the test instead?
    it "starts and is stopped by a signal" do
      interpreter = double(Flapjack::Gateways::Jabber::Interpreter)
      interpreter.should_receive(:respond_to?).with(:interpret).and_return(true)
      interpreter.should_receive(:receive_message).with(nil, 'jim', nil, 'hello!')
      interpreter.should_receive(:receive_message).
        with('flapjacktest@conference.example.com', 'jim', now.to_i, 'hello!')

      client.should_receive(:on_exception)

      msg_client = double('msg_client')
      msg_client.should_receive(:body).and_return('hello!')
      msg_client.should_receive(:from).and_return('jim')
      msg_client.should_receive(:each_element).and_yield([]) # TODO improve

      client.should_receive(:add_message_callback).and_yield(msg_client)

      muc_client.should_receive(:on_message).and_yield(now.to_i, 'jim', 'flapjack: hello!')
      client.should_receive(:is_connected?).times.and_return(true)

      ::Jabber::Client.should_receive(:new).and_return(client)
      ::Jabber::MUC::SimpleMUCClient.should_receive(:new).and_return(muc_client)

      lock.should_receive(:synchronize).and_yield
      stop_cond = double(MonitorMixin::ConditionVariable)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock,
        :stop_condition => stop_cond, :config => config, :logger => @logger)
      stop_cond.should_receive(:wait_until).and_return {
        fjb.instance_variable_set('@should_quit', true)
      }
      fjb.instance_variable_set('@siblings', [interpreter])

      fjb.should_receive(:_join).with(client, muc_clients)
      fjb.should_receive(:_leave).with(client, muc_clients)

      fjb.start
    end

    it "should handle an exception and signal for leave and rejoin"

    it "strips XML from a received string"

    it "handles an announce state change" do
      client.should_receive(:is_connected?).and_return(true)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock,
        :config => config, :logger => @logger)
      fjb.should_receive(:_announce).with(muc_clients)
      fjb.instance_variable_set('@state_buffer', ['announce'])
      fjb.handle_state_change(client, muc_clients)
    end

    it "handles a say state change" do
      client.should_receive(:is_connected?).and_return(true)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock,
        :config => config, :logger => @logger)
      fjb.should_receive(:_say).with(client)
      fjb.instance_variable_set('@state_buffer', ['say'])
      fjb.handle_state_change(client, muc_clients)
    end

    it "handles a leave state change (when connected)" do
      client.should_receive(:is_connected?).and_return(true)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock,
        :config => config, :logger => @logger)
      fjb.should_receive(:_leave).with(client, muc_clients)
      fjb.instance_variable_set('@state_buffer', ['leave'])
      fjb.handle_state_change(client, muc_clients)
    end

    it "handles a leave state change (when not connected)" do
      client.should_receive(:is_connected?).and_return(false)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock,
        :config => config, :logger => @logger)
      fjb.should_receive(:_deactivate).with(muc_clients)
      fjb.instance_variable_set('@state_buffer', ['leave'])
      fjb.handle_state_change(client, muc_clients)
    end

    it "handles a rejoin state change" do
      client.should_receive(:is_connected?).and_return(false)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock,
        :config => config, :logger => @logger)
      fjb.should_receive(:_join).with(client, muc_clients, :rejoin => true)
      fjb.instance_variable_set('@state_buffer', ['rejoin'])
      fjb.handle_state_change(client, muc_clients)
    end

    it "joins the jabber client" do
      client.should_receive(:connect)
      client.should_receive(:auth).with('password')
      client.should_receive(:send).with(an_instance_of(::Jabber::Presence))

      lock.should_receive(:synchronize).twice.and_yield.and_yield

      muc_client.should_receive(:join).with('flapjacktest@conference.example.com/flapjack', nil, :history => false)
      muc_client.should_receive(:say).with(/^flapjack jabber gateway started/)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock,
        :config => config, :logger => @logger)
      fjb._join(client, muc_clients)
    end

    it "rejoins the jabber client" do
      client.should_receive(:connect)
      client.should_receive(:auth).with('password')
      client.should_receive(:send).with(an_instance_of(::Jabber::Presence))

      lock.should_receive(:synchronize).twice.and_yield.and_yield

      muc_client.should_receive(:join).with('flapjacktest@conference.example.com/flapjack', nil, :history => false)
      muc_client.should_receive(:say).with(/^flapjack jabber gateway rejoining/)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock,
        :config => config, :logger => @logger)
      fjb._join(client, muc_clients, :rejoin => true)
    end

    it "leaves the jabber client (connected)" do
      muc_client.should_receive(:active?).and_return(true)
      muc_client.should_receive(:exit)
      client.should_receive(:close)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock,
        :config => config, :logger => @logger)
      fjb.instance_variable_set('@joined', true)
      fjb._leave(client, muc_clients)
    end

    it "deactivates the jabber client (not connected)" do
      muc_client.should_receive(:deactivate)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock,
        :config => config, :logger => @logger)
      fjb._deactivate(muc_clients)
    end

    it "speaks its announce buffer" do
      muc_client.should_receive(:active?).and_return(true)
      muc_client.should_receive(:say).with('hello!')

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock, :config => config, :logger => @logger)
      fjb.instance_variable_set('@announce_buffer', [{:room => 'room1', :msg => 'hello!'}])
      fjb._announce('room1' => muc_client)
    end

    it "speaks its say buffer" do
      message = double(::Jabber::Message)
      ::Jabber::Message.should_receive(:new).
        with('jim', 'hello!').and_return(message)

      client.should_receive(:send).with(message)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock, :config => config, :logger => @logger)
      fjb.instance_variable_set('@say_buffer', [{:nick => 'jim', :msg => 'hello!'}])
      fjb._say(client)
    end

    it "buffers an announce message and sends a signal" do
      lock.should_receive(:synchronize).and_yield
      stop_cond.should_receive(:signal)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock, :stop_condition => stop_cond,
        :config => config, :logger => @logger)
      fjb.announce('room1', 'hello!')
      fjb.instance_variable_get('@state_buffer').should == ['announce']
      fjb.instance_variable_get('@announce_buffer').should == [{:room => 'room1', :msg => 'hello!'}]
    end

    it "buffers a say message and sends a signal" do
      lock.should_receive(:synchronize).and_yield
      stop_cond.should_receive(:signal)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock, :stop_condition => stop_cond,
        :config => config, :logger => @logger)
      fjb.say('jim', 'hello!')
      fjb.instance_variable_get('@state_buffer').should == ['say']
      fjb.instance_variable_get('@say_buffer').should == [{:nick => 'jim', :msg => 'hello!'}]
    end

  end

end
