require 'spec_helper'
require 'flapjack/gateways/jabber'

describe Flapjack::Gateways::Jabber, :logger => true do

  let(:config) { {'queue'    => 'jabber_notifications',
                  'server'   => 'example.com',
                  'port'     => '5222',
                  'jabberid' => 'flapjack@example.com',
                  'password' => 'password',
                  'alias'    => 'flapjack',
                  'identifiers' => ['@flapjack'],
                  'rooms'    => ['flapjacktest@conference.example.com']
                 }
  }


  let(:entity) { double(Flapjack::Data::Entity) }
  let(:check) { double(Flapjack::Data::Check) }

  let(:redis) { double(::Redis) }
  let(:stanza) { double('stanza') }

  let(:now) { Time.now}

  let(:lock) { double(Monitor) }
  let(:stop_cond) { double(MonitorMixin::ConditionVariable) }

  before(:each) do
    allow(Flapjack).to receive(:redis).and_return(redis)
  end

  context 'notifications' do

    let(:queue) { double(Flapjack::RecordQueue) }

    let(:alert) { double(Flapjack::Data::Alert) }

    it "starts and is stopped by an exception" do
      expect(Flapjack::RecordQueue).to receive(:new).with('jabber_notifications',
        Flapjack::Data::Alert).and_return(queue)

      expect(lock).to receive(:synchronize).and_yield
      expect(queue).to receive(:foreach).and_yield(alert)
      expect(queue).to receive(:wait).and_raise(Flapjack::PikeletStop)

      expect(redis).to receive(:quit)

      fjn = Flapjack::Gateways::Jabber::Notifier.new(:lock => lock,
        :config => config, :logger => @logger)
      expect(fjn).to receive(:handle_alert).with(alert)

      expect { fjn.start }.to raise_error(Flapjack::PikeletStop)
    end

    it "handles notifications received via Redis" do
      bot = double(Flapjack::Gateways::Jabber::Bot)
      expect(bot).to receive(:respond_to?).with(:announce).and_return(true)
      expect(bot).to receive(:announce).with('johns@example.com', /Problem: /)
      expect(bot).to receive(:alias).and_return('flapjack')

      expect(entity).to receive(:name).twice.and_return('app-02')
      expect(check).to receive(:entity).twice.and_return(entity)
      expect(check).to receive(:name).twice.and_return('ping')

      expect(alert).to receive(:address).and_return('johns@example.com')
      expect(alert).to receive(:check).twice.and_return(check)
      expect(alert).to receive(:state).and_return('critical')
      expect(alert).to receive(:state_title_case).and_return('Critical')
      expect(alert).to receive(:summary).twice.and_return('')
      expect(alert).to receive(:event_count).and_return(33)
      expect(alert).to receive(:type).twice.and_return('problem')
      expect(alert).to receive(:type_sentence_case).and_return('Problem')
      expect(alert).to receive(:rollup).and_return(nil)
      expect(alert).to receive(:event_hash).and_return('abcd1234')

      fjn = Flapjack::Gateways::Jabber::Notifier.new(:config => config, :logger => @logger)
      fjn.instance_variable_set('@siblings', [bot])
      fjn.send(:handle_alert, alert)
    end

  end

  context 'commands' do

    let(:bot) { double(Flapjack::Gateways::Jabber::Bot) }

    # TODO use separate threads in the test instead?
    it "starts and is stopped by a signal" do
      expect(lock).to receive(:synchronize).and_yield

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:lock => lock, :stop_condition => stop_cond,
        :config => config, :logger => @logger)
      msg = {:room => 'room1', :nick => 'jim', :time => now.to_i, :message => 'help'}
      fji.instance_variable_get('@messages').push(msg)
      expect(stop_cond).to receive(:wait_while) {
        fji.instance_variable_set('@should_quit', true)
      }

      expect(fji).to receive(:interpret).with('room1', 'jim', now.to_i, 'help')

      expect(redis).to receive(:quit)
      fji.start
    end

    it "receives a message and and signals a condition variable" do
      expect(lock).to receive(:synchronize).and_yield

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:lock => lock, :stop_condition => stop_cond,
        :config => config, :logger => @logger)
      expect(fji.instance_variable_get('@messages')).to be_empty
      expect(stop_cond).to receive(:signal)

      fji.receive_message('room1', 'jim', now.to_i, 'help')
      expect(fji.instance_variable_get('@messages').size).to eq(1)
    end

    it "interprets a received help command (from a room)" do
      expect(bot).to receive(:announce).with('room1', /^commands:/)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@bot', bot)
      fji.interpret('room1', 'jim', now.to_i, 'help')
    end

    it "interprets a received help command (from a user)" do
      expect(bot).to receive(:say).with('jim', /^commands:/)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@bot', bot)
      fji.interpret(nil, 'jim', now.to_i, 'help')
    end

    it "interprets a received identify command " do
      expect(bot).to receive(:announce).with('room1', /System CPU Time/)
      expect(bot).to receive(:identifiers).and_return(['@flapjack'])

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config,
              :logger => @logger, :boot_time => now)
      fji.instance_variable_set('@bot', bot)
      fji.interpret('room1', 'jim', now.to_i + 60, 'identify')
    end

    it "interprets a received entity information command" do
      expect(bot).to receive(:announce).with('room1', /Not in scheduled or unscheduled maintenance./)

      all_checks = double('all_checks', :all => [check])
      expect(entity).to receive(:checks).and_return(all_checks)
      all_entities = double('all_entities', :all => [entity])
      expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => 'example.com').and_return(all_entities)

      expect(check).to receive(:name).twice.and_return('ping')
      expect(check).to receive(:scheduled_maintenance_at).and_return(nil)
      expect(check).to receive(:unscheduled_maintenance_at).and_return(nil)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@bot', bot)
      fji.interpret('room1', 'jim', now.to_i, 'tell me about example.com')
    end

    it "handles a message with a newline in it" do
      expect(bot).to receive(:announce).with('room1', /Not in scheduled or unscheduled maintenance./)

      all_checks = double('all_checks', :all => [check])
      expect(entity).to receive(:checks).and_return(all_checks)
      all_entities = double('all_entities', :all => [entity])
      expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => 'example.com').and_return(all_entities)

      expect(check).to receive(:name).twice.and_return('ping')
      expect(check).to receive(:scheduled_maintenance_at).and_return(nil)
      expect(check).to receive(:unscheduled_maintenance_at).and_return(nil)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@bot', bot)
      fji.interpret('room1', 'jim', now.to_i, "tell me \nabout example.com")
    end

    it "interprets a received check information command" do
      expect(bot).to receive(:announce).with('room1', /Not in scheduled or unscheduled maintenance./)

      expect(check).to receive(:scheduled_maintenance_at).and_return(nil)
      expect(check).to receive(:unscheduled_maintenance_at).and_return(nil)

      all_checks = double('all_checks', :all => [check])
      entity_checks = double('entity_checks')
      expect(entity_checks).to receive(:intersect).
        with(:name => 'ping').and_return(all_checks)
      expect(entity).to receive(:checks).and_return(entity_checks)

      all_entities = double('all_entities', :all => [entity])
      expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => 'example.com').and_return(all_entities)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@bot', bot)
      fji.interpret('room1', 'jim', now.to_i, 'tell me about example.com:ping')
    end

    it "interprets a received entity search command" do
      expect(bot).to receive(:announce).with('room1', "found 1 entity matching /example/ ... \nexample.com")

      map_entities = double('all_entities')
      expect(entity).to receive(:name).and_return('example.com')
      expect(map_entities).to receive(:map).and_yield(entity).and_return(['example.com'])
      expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => Regexp.new("example")).and_return(map_entities)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@bot', bot)
      fji.interpret('room1', 'jim', now.to_i, 'find entities matching /example/')
    end

    it "interprets a received entity search command (with an invalid pattern)" do
      expect(bot).to receive(:announce).with('room1', 'that doesn\'t seem to be a valid pattern - /(example/')

      expect(Flapjack::Data::Entity).not_to receive(:intersect)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@bot', bot)
      fji.interpret('room1', 'jim', now.to_i, 'find entities matching /(example/')
    end

    it "interprets a received check acknowledgement command" do
      expect(bot).to receive(:announce).with('room1', 'ACKing ping on example.com (abcd1234)')

      expect(entity).to receive(:name).and_return('example.com')
      expect(check).to receive(:entity).and_return(entity)
      expect(check).to receive(:name).and_return('ping')
      expect(check).to receive(:in_unscheduled_maintenance?).and_return(false)

      all_checks = double('all_checks', :all => [check])
      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:ack_hash => 'abcd1234').and_return(all_checks)

      expect(Flapjack::Data::Event).to receive(:create_acknowledgement).
        with('events', check,
             :summary => 'JJ looking', :acknowledgement_id => 'abcd1234',
             :duration => (60 * 60))

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@bot', bot)
      fji.interpret('room1', 'jim', now.to_i, 'ACKID abcd1234 JJ looking duration: 1 hour')
    end

    it "interprets a received notification test command" do
      expect(bot).to receive(:announce).with('room1', /so you want me to test notifications/)

      all_entities = double('all_entities', :all => [entity])
      expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => 'example.com').and_return(all_entities)

      expect(Flapjack::Data::Event).to receive(:test_notifications).with('events', entity,
        nil, :summary => an_instance_of(String))

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@bot', bot)
      fji.interpret('room1', 'jim', now.to_i, 'test notifications for example.com')
    end

    it "interprets a received notification test command (for a missing entity)" do
      expect(bot).to receive(:announce).with('room1', "yeah, no I can't see entity: 'example.com' in my systems")

      no_entities = double('no_entities', :all => [])
      expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => 'example.com').and_return(no_entities)

      expect(Flapjack::Data::Event).not_to receive(:test_notifications)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@bot', bot)
      fji.interpret('room1', 'jim', now.to_i, 'test notifications for example.com')
    end

    it "doesn't interpret an unmatched command" do
      expect(bot).to receive(:announce).with('room1', /^what do you mean/)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@bot', bot)
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
      expect(interpreter).to receive(:respond_to?).with(:interpret).and_return(true)
      expect(interpreter).to receive(:receive_message).with(nil, 'jim', nil, 'hello!')

      expect(client).to receive(:on_exception)

      msg_client = double('msg_client')
      expect(msg_client).to receive(:body).and_return('hello!')
      expect(msg_client).to receive(:from).and_return('jim')
      expect(msg_client).to receive(:each_element).and_yield([]) # TODO improve

      expect(client).to receive(:add_message_callback).and_yield(msg_client)

      expect(muc_client).to receive(:on_message).and_yield(now.to_i, 'jim', 'flapjack: hello!')
      expect(client).to receive(:is_connected?).times.and_return(true)

      expect(::Jabber::Client).to receive(:new).and_return(client)
      expect(::Jabber::MUC::SimpleMUCClient).to receive(:new).and_return(muc_client)

      expect(lock).to receive(:synchronize).and_yield
      stop_cond = double(MonitorMixin::ConditionVariable)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock,
        :stop_condition => stop_cond, :config => config, :logger => @logger)
      expect(stop_cond).to receive(:wait_until) {
        fjb.instance_variable_set('@should_quit', true)
      }
      fjb.instance_variable_set('@siblings', [interpreter])

      expect(fjb).to receive(:_join).with(client, muc_clients)
      expect(fjb).to receive(:_leave).with(client, muc_clients)

      fjb.start
    end

    it "should handle an exception and signal for leave and rejoin"

    it "strips XML from a received string"

    it "handles an announce state change" do
      expect(client).to receive(:is_connected?).and_return(true)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock,
        :config => config, :logger => @logger)
      expect(fjb).to receive(:_announce).with(muc_clients)
      fjb.instance_variable_set('@state_buffer', ['announce'])
      fjb.handle_state_change(client, muc_clients)
    end

    it "handles a say state change" do
      expect(client).to receive(:is_connected?).and_return(true)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock,
        :config => config, :logger => @logger)
      expect(fjb).to receive(:_say).with(client)
      fjb.instance_variable_set('@state_buffer', ['say'])
      fjb.handle_state_change(client, muc_clients)
    end

    it "handles a leave state change (when connected)" do
      expect(client).to receive(:is_connected?).and_return(true)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock,
        :config => config, :logger => @logger)
      expect(fjb).to receive(:_leave).with(client, muc_clients)
      fjb.instance_variable_set('@state_buffer', ['leave'])
      fjb.handle_state_change(client, muc_clients)
    end

    it "handles a leave state change (when not connected)" do
      expect(client).to receive(:is_connected?).and_return(false)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock,
        :config => config, :logger => @logger)
      expect(fjb).to receive(:_deactivate).with(muc_clients)
      fjb.instance_variable_set('@state_buffer', ['leave'])
      fjb.handle_state_change(client, muc_clients)
    end

    it "handles a rejoin state change" do
      expect(client).to receive(:is_connected?).and_return(false)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock,
        :config => config, :logger => @logger)
      expect(fjb).to receive(:_join).with(client, muc_clients, :rejoin => true)
      fjb.instance_variable_set('@state_buffer', ['rejoin'])
      fjb.handle_state_change(client, muc_clients)
    end

    it "joins the jabber client" do
      expect(client).to receive(:connect)
      expect(client).to receive(:auth).with('password')
      expect(client).to receive(:send).with(an_instance_of(::Jabber::Presence))

      expect(lock).to receive(:synchronize).twice.and_yield.and_yield

      expect(muc_client).to receive(:join).with('flapjacktest@conference.example.com/flapjack', nil, :history => false)
      expect(muc_client).to receive(:say).with(/^flapjack jabber gateway started/)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock,
        :config => config, :logger => @logger)
      fjb._join(client, muc_clients)
    end

    it "rejoins the jabber client" do
      expect(client).to receive(:connect)
      expect(client).to receive(:auth).with('password')
      expect(client).to receive(:send).with(an_instance_of(::Jabber::Presence))

      expect(lock).to receive(:synchronize).twice.and_yield.and_yield

      expect(muc_client).to receive(:join).with('flapjacktest@conference.example.com/flapjack', nil, :history => false)
      expect(muc_client).to receive(:say).with(/^flapjack jabber gateway rejoining/)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock,
        :config => config, :logger => @logger)
      fjb._join(client, muc_clients, :rejoin => true)
    end

    it "leaves the jabber client (connected)" do
      expect(muc_client).to receive(:active?).and_return(true)
      expect(muc_client).to receive(:exit)
      expect(client).to receive(:close)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock,
        :config => config, :logger => @logger)
      fjb.instance_variable_set('@joined', true)
      fjb._leave(client, muc_clients)
    end

    it "deactivates the jabber client (not connected)" do
      expect(muc_client).to receive(:deactivate)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock,
        :config => config, :logger => @logger)
      fjb._deactivate(muc_clients)
    end

    it "speaks its announce buffer" do
      expect(muc_client).to receive(:active?).and_return(true)
      expect(muc_client).to receive(:say).with('hello!')

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock, :config => config, :logger => @logger)
      fjb.instance_variable_set('@announce_buffer', [{:room => 'room1', :msg => 'hello!'}])
      fjb._announce('room1' => muc_client)
    end

    it "speaks its say buffer" do
      message = double(::Jabber::Message)
      expect(::Jabber::Message).to receive(:new).
        with('jim', 'hello!').and_return(message)

      expect(client).to receive(:send).with(message)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock, :config => config, :logger => @logger)
      fjb.instance_variable_set('@say_buffer', [{:nick => 'jim', :msg => 'hello!'}])
      fjb._say(client)
    end

    it "buffers an announce message and sends a signal" do
      expect(lock).to receive(:synchronize).and_yield
      expect(stop_cond).to receive(:signal)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock, :stop_condition => stop_cond,
        :config => config, :logger => @logger)
      fjb.announce('room1', 'hello!')
      expect(fjb.instance_variable_get('@state_buffer')).to eq(['announce'])
      expect(fjb.instance_variable_get('@announce_buffer')).to eq([{:room => 'room1', :msg => 'hello!'}])
    end

    it "buffers a say message and sends a signal" do
      expect(lock).to receive(:synchronize).and_yield
      expect(stop_cond).to receive(:signal)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock, :stop_condition => stop_cond,
        :config => config, :logger => @logger)
      fjb.say('jim', 'hello!')
      expect(fjb.instance_variable_get('@state_buffer')).to eq(['say'])
      expect(fjb.instance_variable_get('@say_buffer')).to eq([{:nick => 'jim', :msg => 'hello!'}])
    end

  end

end
