require 'spec_helper'
require 'flapjack/gateways/web'

describe Flapjack::Gateways::Web, :sinatra => true, :logger => true do

  def app
    Flapjack::Gateways::Web
  end

  let(:entity_name)     { 'foo-app-01.example.com'}
  let(:entity_name_esc) { CGI.escape(entity_name) }
  let(:check)           { 'ping' }

  let(:entity)          { double(Flapjack::Data::Entity) }
  let(:entity_check)    { double(Flapjack::Data::EntityCheck) }

  let(:redis) { double('redis') }

  before(:all) do
    Flapjack::Gateways::Web.class_eval {
      set :raise_errors, true
      set :show_exceptions, false
    }
  end

  def expect_stats
    expect(redis).to receive(:dbsize).and_return(3)
    expect(redis).to receive(:keys).with('executive_instance:*').and_return(["executive_instance:foo-app-01"])
    expect(redis).to receive(:hget).once.and_return(Time.now.to_i - 60)
    expect(redis).to receive(:hgetall).twice.and_return({'all' => '8001', 'ok' => '8002'},
      {'all' => '9001', 'ok' => '9002'})
    expect(redis).to receive(:llen).with('events')
    expect(Flapjack::Data::EntityCheck).to receive(:find_all_split_by_freshness).
      and_return(30 => 3)
  end

  def expect_check_stats
    expect(Flapjack::Data::EntityCheck).to receive(:count_current).
      with(:redis => redis).and_return(1)
    expect(Flapjack::Data::EntityCheck).to receive(:count_current_failing).
      with(:redis => redis).and_return(1)
  end

  def expect_entity_stats
    expect(Flapjack::Data::Entity).to receive(:all).
      with(:enabled => true, :redis => redis).and_return([entity_name])
    expect(Flapjack::Data::Entity).to receive(:find_all_names_with_failing_checks).
      with(:redis => redis).and_return([entity_name])
  end

  def expect_entity_check_status(ec)
    time = Time.now.to_i

    expect(ec).to receive(:state).and_return('ok')
    expect(ec).to receive(:summary).and_return('happy results are returned')
    expect(ec).to receive(:last_update).and_return(time - (3 * 60 * 60))
    expect(ec).to receive(:last_change).and_return(time - (3 * 60 * 60))
    expect(ec).to receive(:last_notification_for_state).with(:problem).and_return({:timestamp => time - ((3 * 60 * 60) + (5 * 60))})
    expect(ec).to receive(:last_notification_for_state).with(:recovery).and_return({:timestamp => time - (3 * 60 * 60)})
    expect(ec).to receive(:last_notification_for_state).with(:acknowledgement).and_return({:timestamp => nil})
    expect(ec).to receive(:in_scheduled_maintenance?).and_return(false)
    expect(ec).to receive(:in_unscheduled_maintenance?).and_return(false)
  end

  context "Web page design" do

    before(:each) do
      expect(Flapjack::RedisPool).to receive(:new).and_return(redis)
      Flapjack::Gateways::Web.instance_variable_set('@logger', @logger)
    end

    it "displays a custom logo if configured" do
      image_path = '/tmp/branding.png'
      config = {"logo_image_path" => image_path}

      allow(File).to receive(:file?).and_call_original
      allow(File).to receive(:file?).with(image_path) { true }

      Flapjack::Gateways::Web.instance_variable_set('@config', config)
      Flapjack::Gateways::Web.start

      # NOTE Reuse enough of the stats specs to be able to build a page quickly
      expect_stats
      expect_check_stats
      expect_entity_stats

      logo_image_tag = '<img alt="Flapjack" class="logo" src="/img/branding.png">'

      aget '/self_stats'
      expect( last_response.body ).to include(logo_image_tag)
    end

    it "displays the standard logo if no custom logo configured" do
      Flapjack::Gateways::Web.instance_variable_set('@config', {})
      Flapjack::Gateways::Web.start
      # NOTE Reuse enough of the stats specs to be able to build a page quickly
      expect_stats
      expect_check_stats
      expect_entity_stats

      logo_image_tag = '<img alt="Flapjack" class="logo" src="/img/flapjack-2013-notext-transparent-300-300.png">'

      aget '/self_stats'

      expect( last_response.body ).to include(logo_image_tag)
    end
  end

  context "Web page behavior" do

    before(:each) do
      expect(Flapjack::RedisPool).to receive(:new).and_return(redis)
      Flapjack::Gateways::Web.instance_variable_set('@config', {})
      Flapjack::Gateways::Web.instance_variable_set('@logger', @logger)
      Flapjack::Gateways::Web.start
    end

    # TODO add data, test that pages contain representations of it
    # (for the methods that access redis directly)

    it "shows a page listing all checks" do
      #redis.should_receive(:keys).with('*:*:states').and_return(["#{entity_name}:#{check}"])
      expect(Flapjack::Data::EntityCheck).to receive(:find_current_names_by_entity).
        with(:redis => redis).and_return({entity_name => [check]})
      expect_check_stats

      expect_entity_check_status(entity_check)

      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, hash_including(:redis => redis)).twice.and_return(entity)

      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity, 'ping', :redis => redis).and_return(entity_check)

      aget '/checks_all'
      expect(last_response).to be_ok
    end

    it "shows a page listing failing checks" do
      #redis.should_receive(:zrange).with('failed_checks', 0, -1).and_return(["#{entity_name}:#{check}"])

      expect_check_stats

      expect_entity_check_status(entity_check)

      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      expect(Flapjack::Data::EntityCheck).to receive(:find_current_names_failing_by_entity).
        with(:redis => redis).and_return({entity_name => [check]})

      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity, 'ping', :redis => redis).and_return(entity_check)
      aget '/checks_failing'
      expect(last_response).to be_ok
    end

    it "shows a page listing flapjack statistics" do
      #redis.should_receive(:keys).with('check:*').and_return([])
      #redis.should_receive(:zrange).with('failed_checks', 0, -1).and_return(["#{entity_name}:#{check}"])
      expect_stats
      expect_check_stats
      expect_entity_stats

      aget '/self_stats'
      # p @logger.messages
      expect(last_response).to be_ok
    end

    it "shows the state of a check for an entity" do
      time = Time.now
      expect(Time).to receive(:now).exactly(5).times.and_return(time)

      last_notifications = {:problem         => {:timestamp => time.to_i - ((3 * 60 * 60) + (5 * 60)), :summary => 'prob'},
                            :recovery        => {:timestamp => time.to_i - (3 * 60 * 60), :summary => nil},
                            :acknowledgement => {:timestamp => nil, :summary => nil} }

      expect(entity_check).to receive(:state).and_return('ok')
      expect(entity_check).to receive(:last_update).and_return(time.to_i - (3 * 60 * 60))
      expect(entity_check).to receive(:last_change).and_return(time.to_i - (3 * 60 * 60))
      expect(entity_check).to receive(:summary).and_return('all good')
      expect(entity_check).to receive(:details).and_return('seriously, all very wonderful')
      expect(entity_check).to receive(:perfdata).and_return([{"key" => "foo", "value" => "bar"}])
      expect(entity_check).to receive(:last_notifications_of_each_type).and_return(last_notifications)
      expect(entity_check).to receive(:maintenances).with(nil, nil, :scheduled => true).and_return([])
      expect(entity_check).to receive(:failed?).and_return(false)
      expect(entity_check).to receive(:tags_saved).and_return(['tag1', 'tag2'])
      expect(entity_check).to receive(:current_maintenance).with(:scheduled => true).and_return(false)
      expect(entity_check).to receive(:current_maintenance).with(:scheduled => false).and_return(false)
      expect(entity_check).to receive(:contacts).and_return([])
      expect(entity_check).to receive(:historical_states).
        with(nil, time.to_i, :order => 'desc', :limit => 20).and_return([])
      expect(entity_check).to receive(:enabled?).and_return(true)
      expect(entity_check).to receive(:initial_failure_delay).exactly(2).times.and_return(30)
      expect(entity_check).to receive(:repeat_failure_delay).exactly(2).times.and_return(60)

      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity, 'ping', :redis => redis).and_return(entity_check)

      aget "/check?entity=#{entity_name_esc}&check=ping"
      expect(last_response).to be_ok
      # TODO test instance variables set to appropriate values
    end

    it "returns 404 if an unknown entity is requested" do
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name_esc, :redis => redis).and_return(nil)

      aget "/check?entity=#{entity_name_esc}&check=ping"
      expect(last_response).to be_not_found
    end

    # TODO shouldn't create actual entity record
    it "returns 404 if no entity check is passed" do
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      aget "/check?entity=#{entity_name_esc}"
      expect(last_response).to be_not_found
    end

    it "creates an acknowledgement for an entity check" do
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity, 'ping', :redis => redis).and_return(entity_check)

      expect(Flapjack::Data::Event).to receive(:create_acknowledgement).
        with(entity_name, 'ping', :summary => "", :duration => (4 * 60 * 60),
             :acknowledgement_id => '1234', :redis => redis)

      apost "/acknowledgements/#{entity_name_esc}/ping?acknowledgement_id=1234"
      expect(last_response.status).to eq(302)
    end

    it "creates a scheduled maintenance period for an entity check" do
      t = Time.now.to_i

      start_time = Time.at(t - (24 * 60 * 60))
      duration = 30 * 60
      summary = 'wow'

      expect(Chronic).to receive(:parse).with('1 day ago').and_return(start_time)
      expect(ChronicDuration).to receive(:parse).with('30 minutes').and_return(duration)

      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity, 'ping', :redis => redis).and_return(entity_check)

      expect(entity_check).to receive(:create_scheduled_maintenance).
        with(start_time.to_i, duration, :summary => summary)

      apost "/scheduled_maintenances/#{entity_name_esc}/ping?"+
        "start_time=1+day+ago&duration=30+minutes&summary=wow"

      expect(last_response.status).to eq(302)
    end

    it "deletes a scheduled maintenance period for an entity check" do
      t = Time.now.to_i

      start_time = t - (24 * 60 * 60)

      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity, 'ping', :redis => redis).and_return(entity_check)

      expect(entity_check).to receive(:end_scheduled_maintenance).with(start_time)

      adelete "/scheduled_maintenances/#{entity_name_esc}/ping?start_time=#{start_time}"
      expect(last_response.status).to eq(302)
    end

    it "shows a list of all known contacts" do
      expect(Flapjack::Data::Contact).to receive(:all)

      aget "/contacts"
      expect(last_response).to be_ok
    end

    it "shows details of an individual contact found by id" do
      contact = double('contact')
      expect(contact).to receive(:name).and_return("Smithson Smith")
      expect(contact).to receive(:media).exactly(3).times.and_return({})
      expect(contact).to receive(:entities).with(:checks => true).and_return([])
      expect(contact).to receive(:notification_rules).and_return([])

      expect(Flapjack::Data::Contact).to receive(:find_by_id).
        with('0362', :redis => redis).and_return(contact)

      aget "/contacts/0362"
      expect(last_response).to be_ok
    end
  end


end
