require 'spec_helper'
require 'flapjack/gateways/web'

describe Flapjack::Gateways::Web, :sinatra => true, :logger => true do

  def app
    Flapjack::Gateways::Web
  end

  let(:entity_name)     { 'example.com'}
  let(:entity_name_esc) { CGI.escape(entity_name) }
  let(:check)           { 'ping' }

  let(:entity)          { mock(Flapjack::Data::Entity) }
  let(:entity_check)    { mock(Flapjack::Data::EntityCheck) }

  let(:redis) { mock(Redis) }

  before(:all) do
    Flapjack::Gateways::Web.class_eval {
      set :show_exceptions, false
    }
  end

  before(:each) do
    Flapjack.stub(:redis).and_return(redis)
    Flapjack::Gateways::Web.instance_variable_set('@config', {})
    Flapjack::Gateways::Web.instance_variable_set('@logger', @logger)
    Flapjack::Gateways::Web.start
  end

  def expect_stats
    redis.should_receive(:dbsize).and_return(3)
    redis.should_receive(:keys).with('executive_instance:*').and_return(["executive_instance:foo-app-01"])
    redis.should_receive(:hget).twice.and_return(Time.now.to_i - 60)
    redis.should_receive(:hgetall).twice.and_return({'all' => '8001', 'ok' => '8002'},
      {'all' => '9001', 'ok' => '9002'})
    redis.should_receive(:llen).with('events')
  end

  def expect_check_stats
    Flapjack::Data::EntityCheck.should_receive(:count_all).
      and_return(1)
    Flapjack::Data::EntityCheck.should_receive(:count_all_failing).
      and_return(1)
  end

  def expect_entity_stats
    Flapjack::Data::Entity.should_receive(:find_all_with_checks).
      and_return([entity_name])
    Flapjack::Data::Entity.should_receive(:find_all_with_failing_checks).
      and_return([entity_name])
  end

  def expect_entity_check_status(ec)
    time = Time.now.to_i

    ec.should_receive(:state).and_return('ok')
    ec.should_receive(:summary).and_return('happy results are returned')
    ec.should_receive(:last_update).and_return(time - (3 * 60 * 60))
    ec.should_receive(:last_change).and_return(time - (3 * 60 * 60))
    ec.should_receive(:last_notification_for_state).with(:problem).and_return({:timestamp => time - ((3 * 60 * 60) + (5 * 60))})
    ec.should_receive(:last_notification_for_state).with(:recovery).and_return({:timestamp => time - (3 * 60 * 60)})
    ec.should_receive(:last_notification_for_state).with(:acknowledgement).and_return({:timestamp => nil})
    ec.should_receive(:in_scheduled_maintenance?).and_return(false)
    ec.should_receive(:in_unscheduled_maintenance?).and_return(false)
  end

  # TODO add data, test that pages contain representations of it
  # (for the methods that access redis directly)

  it "shows a page listing all checks" do
    #redis.should_receive(:keys).with('*:*:states').and_return(["#{entity_name}:#{check}"])
    Flapjack::Data::EntityCheck.should_receive(:find_all_by_entity).
      and_return({entity_name => [check]})
    expect_check_stats

    expect_entity_check_status(entity_check)

    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name).and_return(entity)

    Flapjack::Data::EntityCheck.should_receive(:for_entity).
      with(entity, 'ping').and_return(entity_check)

    get '/checks_all'
    last_response.should be_ok
  end

  it "shows a page listing failing checks" do
    #redis.should_receive(:zrange).with('failed_checks', 0, -1).and_return(["#{entity_name}:#{check}"])

    expect_check_stats

    expect_entity_check_status(entity_check)

    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name).and_return(entity)

    Flapjack::Data::EntityCheck.should_receive(:find_all_failing_by_entity).
      and_return({entity_name => [check]})

    Flapjack::Data::EntityCheck.should_receive(:for_entity).
      with(entity, 'ping').and_return(entity_check)
    get '/checks_failing'
    last_response.should be_ok
  end

  it "shows a page listing flapjack statistics" do
    #redis.should_receive(:keys).with('check:*').and_return([])
    #redis.should_receive(:zrange).with('failed_checks', 0, -1).and_return(["#{entity_name}:#{check}"])
    expect_stats
    expect_check_stats
    expect_entity_stats

    get '/self_stats'
    last_response.should be_ok
  end

  it "shows the state of a check for an entity" do
    time = Time.now
    Time.should_receive(:now).exactly(5).times.and_return(time)

    last_notifications = {:problem         => {:timestamp => time.to_i - ((3 * 60 * 60) + (5 * 60)), :summary => 'prob'},
                          :recovery        => {:timestamp => time.to_i - (3 * 60 * 60), :summary => nil},
                          :acknowledgement => {:timestamp => nil, :summary => nil} }

    expect_check_stats
    entity_check.should_receive(:state).and_return('ok')
    entity_check.should_receive(:last_update).and_return(time.to_i - (3 * 60 * 60))
    entity_check.should_receive(:last_change).and_return(time.to_i - (3 * 60 * 60))
    entity_check.should_receive(:summary).and_return('all good')
    entity_check.should_receive(:details).and_return('seriously, all very wonderful')
    entity_check.should_receive(:last_notifications_of_each_type).and_return(last_notifications)
    entity_check.should_receive(:maintenances).with(nil, nil, :scheduled => true).and_return([])
    entity_check.should_receive(:failed?).and_return(false)
    entity_check.should_receive(:current_maintenance).with(:scheduled => true).and_return(false)
    entity_check.should_receive(:current_maintenance).with(:scheduled => false).and_return(false)
    entity_check.should_receive(:contacts).and_return([])
    entity_check.should_receive(:historical_states).
      with(nil, time.to_i, :order => 'desc', :limit => 20).and_return([])
    entity_check.should_receive(:enabled?).with().
      and_return(true)

    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name).and_return(entity)

    Flapjack::Data::EntityCheck.should_receive(:for_entity).
      with(entity, 'ping').and_return(entity_check)

    get "/check?entity=#{entity_name_esc}&check=ping"
    last_response.should be_ok
    # TODO test instance variables set to appropriate values
  end

  it "returns 404 if an unknown entity is requested" do
    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name_esc).and_return(nil)

    get "/check?entity=#{entity_name_esc}&check=ping"
    last_response.should be_not_found
  end

  # TODO shouldn't create actual entity record
  it "returns 404 if no entity check is passed" do
    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name).and_return(entity)

    get "/check?entity=#{entity_name_esc}"
    last_response.should be_not_found
  end

  it "creates an acknowledgement for an entity check" do
    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name).and_return(entity)

    Flapjack::Data::EntityCheck.should_receive(:for_entity).
      with(entity, 'ping').and_return(entity_check)

    Flapjack::Data::Event.should_receive(:create_acknowledgement).
      with('events', entity_name, 'ping', :summary => "", :duration => (4 * 60 * 60),
           :acknowledgement_id => '1234')

    post "/acknowledgements/#{entity_name_esc}/ping?acknowledgement_id=1234"
    last_response.status.should == 302
  end

  it "creates a scheduled maintenance period for an entity check" do
    t = Time.now.to_i

    start_time = Time.at(t - (24 * 60 * 60))
    duration = 30 * 60
    summary = 'wow'

    Chronic.should_receive(:parse).with('1 day ago').and_return(start_time)
    ChronicDuration.should_receive(:parse).with('30 minutes').and_return(duration)

    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name).and_return(entity)

    Flapjack::Data::EntityCheck.should_receive(:for_entity).
      with(entity, 'ping').and_return(entity_check)

    entity_check.should_receive(:create_scheduled_maintenance).
      with(start_time.to_i, duration, :summary => summary)

    post "/scheduled_maintenances/#{entity_name_esc}/ping?"+
      "start_time=1+day+ago&duration=30+minutes&summary=wow"

    last_response.status.should == 302
  end

  it "deletes a scheduled maintenance period for an entity check" do
    t = Time.now.to_i

    start_time = t - (24 * 60 * 60)

    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name).and_return(entity)

    Flapjack::Data::EntityCheck.should_receive(:for_entity).
      with(entity, 'ping').and_return(entity_check)

    entity_check.should_receive(:end_scheduled_maintenance).with(start_time)

    delete "/scheduled_maintenances/#{entity_name_esc}/ping?start_time=#{start_time}"
    last_response.status.should == 302
  end

  it "shows a list of all known contacts" do
    Flapjack::Data::Contact.should_receive(:all)

    get "/contacts"
    last_response.should be_ok
  end

  it "shows details of an individual contact found by id" do
    contact = mock('contact')
    contact.should_receive(:name).twice.and_return("Smithson Smith")
    contact.should_receive(:media).exactly(3).times.and_return({})
    contact.should_receive(:entities).with(:checks => true).and_return([])
    contact.should_receive(:notification_rules).and_return([])

    Flapjack::Data::Contact.should_receive(:find_by_id).
      with('0362').and_return(contact)

    get "/contacts/0362"
    last_response.should be_ok
  end

end
