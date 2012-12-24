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

  let(:redis) { mock('redis') }

  before(:each) do
    Flapjack::RedisPool.should_receive(:new).and_return(redis)
    Flapjack::Gateways::Web.instance_variable_set('@config', {})
    Flapjack::Gateways::Web.instance_variable_set('@logger', @logger)
    Flapjack::Gateways::Web.start
  end

  def expect_stats
    redis.should_receive(:keys).with('*').and_return([])
    redis.should_receive(:zcard).with('failed_checks')
    redis.should_receive(:keys).with('check:*:*').and_return([])
    redis.should_receive(:zscore).with('executive_instances', anything).and_return(Time.now.to_i)
    redis.should_receive(:hgetall).twice.and_return({'all' => '8001', 'ok' => '8002'},
      {'all' => '9001', 'ok' => '9002'})
    redis.should_receive(:llen).with('events')
  end

  def expect_entity_check_status(ec)
    time = Time.now.to_i

    ec.should_receive(:state).and_return('ok')
    ec.should_receive(:last_update).and_return(time - (3 * 60 * 60))
    ec.should_receive(:last_change).and_return(time - (3 * 60 * 60))
    ec.should_receive(:last_problem_notification).and_return(time - ((3 * 60 * 60) + (5 * 60)))
    ec.should_receive(:last_recovery_notification).and_return(time - (3 * 60 * 60))
    ec.should_receive(:last_acknowledgement_notification).and_return(nil)
    ec.should_receive(:in_scheduled_maintenance?).and_return(false)
    ec.should_receive(:in_unscheduled_maintenance?).and_return(false)
  end

  # TODO add data, test that pages contain representations of it
  # (for the methods that access redis directly)

  it "shows a page listing all checks" do
    redis.should_receive(:keys).with('*:*:states').and_return(["#{entity_name}:#{check}:states"])

    expect_stats

    redis.should_receive(:zrange).with("executive_instances", "0", "-1", :withscores => true)

    expect_entity_check_status(entity_check)

    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    Flapjack::Data::EntityCheck.should_receive(:for_entity).
      with(entity, 'ping', :redis => redis).and_return(entity_check)

    get '/'
    last_response.should be_ok
  end

  it "shows a page listing failing checks" do
    redis.should_receive(:zrange).with("executive_instances", "0", "-1", :withscores => true)
    redis.should_receive(:zrange).with('failed_checks', 0, -1).and_return(["#{entity_name}:#{check}:states"])

    expect_stats

    expect_entity_check_status(entity_check)

    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    Flapjack::Data::EntityCheck.should_receive(:for_entity).
      with(entity, 'ping', :redis => redis).and_return(entity_check)
    get '/failing'
    last_response.should be_ok
  end

  it "shows a page listing flapjack statistics" do
    expect_stats
    redis.should_receive(:zrange).with("executive_instances", "0", "-1", :withscores => true)

    get '/self_stats'
    last_response.should be_ok
  end

  it "shows the state of a check for an entity" do
    time = Time.now.to_i

    last_notifications = {:problem         => time - ((3 * 60 * 60) + (5 * 60)),
                          :recovery        => time - (3 * 60 * 60),
                          :acknowledgement => nil }

    entity_check.should_receive(:state).and_return('ok')
    entity_check.should_receive(:last_update).and_return(time - (3 * 60 * 60))
    entity_check.should_receive(:last_change).and_return(time - (3 * 60 * 60))
    entity_check.should_receive(:summary).and_return('all good')
    entity_check.should_receive(:last_notifications_of_each_type).and_return(last_notifications)
    entity_check.should_receive(:maintenances).with(nil, nil, :scheduled => true).and_return([])
    entity_check.should_receive(:failed?).and_return(false)
    entity_check.should_receive(:current_maintenance).with(:scheduled => true).and_return(false)
    entity_check.should_receive(:current_maintenance).with(:scheduled => false).and_return(false)
    entity_check.should_receive(:contacts).and_return([])

    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    Flapjack::Data::EntityCheck.should_receive(:for_entity).
      with(entity, 'ping', :redis => redis).and_return(entity_check)

    get "/check?entity=#{entity_name_esc}&check=ping"
    last_response.should be_ok
    # TODO test instance variables set to appropriate values
  end

  it "returns 404 if an unknown entity is requested" do
    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name_esc, :redis => redis).and_return(nil)

    get "/check?entity=#{entity_name_esc}&check=ping"
    last_response.should be_not_found
  end

  # TODO shouldn't create actual entity record
  it "returns 404 if no entity check is passed" do
    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    get "/check?entity=#{entity_name_esc}"
    last_response.should be_not_found
  end

  it "creates an acknowledgement for an entity check" do
    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    Flapjack::Data::EntityCheck.should_receive(:for_entity).
      with(entity, 'ping', :redis => redis).and_return(entity_check)

    entity_check.should_receive(:create_acknowledgement).
      with(an_instance_of(Hash))

    post "/acknowledgements/#{entity_name_esc}/ping"
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
      with(entity_name, :redis => redis).and_return(entity)

    Flapjack::Data::EntityCheck.should_receive(:for_entity).
      with(entity, 'ping', :redis => redis).and_return(entity_check)

    entity_check.should_receive(:create_scheduled_maintenance).
      with(:start_time => start_time.to_i, :duration => duration, :summary => summary)

    post "/scheduled_maintenances/#{entity_name_esc}/ping?"+
      "start_time=1+day+ago&duration=30+minutes&summary=wow"
    last_response.status.should == 302
  end

  it "updates a scheduled maintenance period for an entity check" do
    t = Time.new.to_i

    start_time = t - (24 * 60 * 60)

    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    Flapjack::Data::EntityCheck.should_receive(:for_entity).
      with(entity, 'ping', :redis => redis).and_return(entity_check)

    Chronic.should_receive(:parse).with('now').and_return(t)

    entity_check.should_receive(:update_scheduled_maintenance).
      with(start_time, {:end_time => t})

    patch "/scheduled_maintenances/#{entity_name_esc}/ping",
      {"start_time" => start_time, "end_time" => 'now'}
    last_response.status.should == 302
  end

  it "deletes a scheduled maintenance period for an entity check" do
    t = Time.now.to_i

    start_time = t - (24 * 60 * 60)

    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    Flapjack::Data::EntityCheck.should_receive(:for_entity).
      with(entity, 'ping', :redis => redis).and_return(entity_check)

    entity_check.should_receive(:delete_scheduled_maintenance).
      with(:start_time => start_time)

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
    contact.should_receive(:entities_and_checks).and_return([])

    Flapjack::Data::Contact.should_receive(:find_by_id).
      with('0362', :redis => redis).and_return(contact)

    get "/contacts/0362"
    last_response.should be_ok
  end

end
