require 'spec_helper'
require 'flapjack/gateways/web'

describe Flapjack::Gateways::Web, :sinatra => true, :logger => true do

  def app
    Flapjack::Gateways::Web
  end

  let(:entity_name)     { 'example.com'}
  let(:entity_name_esc) { CGI.escape(entity_name) }
  let(:check)           { 'ping' }

  let(:entity)          { double(Flapjack::Data::Entity) }
  let(:entity_check)    { double(Flapjack::Data::Check) }

  let(:redis) { double(Redis) }

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
    redis.should_receive(:hget).once.and_return(Time.now.to_i - 60)
    redis.should_receive(:hgetall).twice.and_return({'all' => '8001', 'ok' => '8002'},
      {'all' => '9001', 'ok' => '9002'})
    redis.should_receive(:llen).with('events')
  end

  let(:failing_checks) { double('failing_checks') }

  def expect_check_stats
    Flapjack::Data::Check.should_receive(:count).and_return(1)

    failing_checks.should_receive(:count).and_return(1)
  end

  def expect_entity_stats
    enabled_count = double('enabled_count', :count => 1)
    Flapjack::Data::Entity.should_receive(:intersect).with(:enabled =>
      true).and_return(enabled_count)

    # entity.should_receive(:name).and_return('foo.example.com')

    failing_enabled = double('failing_enabled', :all => [entity_check])
    failing_checks.should_receive(:intersect).with(:enabled => true).
      and_return(failing_enabled)
  end

  def expect_entity_check_status(ec)
    time = Time.now.to_i

    ec.should_receive(:state).and_return('ok')
    ec.should_receive(:summary).and_return('happy results are returned')
    ec.should_receive(:last_update).and_return(time - (3 * 60 * 60))

    last_failing = double('last_failing',
      :last => double(Flapjack::Data::CheckState, :timestamp => time - ((3 * 60 * 60) + (5 * 60))))
    ok_state = double(Flapjack::Data::CheckState, :timestamp => time - ((3 * 60 * 60)))
    last_ok = double('last_ok', :last => ok_state)
    no_last_ack = double('no_last_ack', :last => nil)

    states = double('states')
    states.should_receive(:intersect).with(:state => ['critical', 'warning', 'unknown'], :notified => true).
      and_return(last_failing)
    states.should_receive(:intersect).with(:state => 'ok', :notified => true).
      and_return(last_ok)
    states.should_receive(:intersect).with(:state => 'acknowledgement', :notified => true).
      and_return(no_last_ack)
    states.should_receive(:last).and_return(ok_state)

    ec.should_receive(:states).exactly(4).times.and_return(states)

    ec.should_receive(:in_scheduled_maintenance?).and_return(false)
    ec.should_receive(:in_unscheduled_maintenance?).and_return(false)
  end

  # TODO add data, test that pages contain representations of it
  # (for the methods that access redis directly)

  it "shows a page listing all checks" do
    expect_check_stats

    expect_entity_check_status(entity_check)

    entity_check.should_receive(:entity_name).and_return('foo')
    entity_check.should_receive(:name).twice.and_return('ping')
    Flapjack::Data::Check.should_receive(:all).and_return([entity_check])

    Flapjack::Data::Check.should_receive(:intersect).
      with(:state => ['critical', 'warning', 'unknown']).
      and_return(failing_checks)

    get '/checks_all'
    last_response.should be_ok
  end

  it "shows a page listing failing checks" do
    expect_check_stats

    expect_entity_check_status(entity_check)

    entity_check.should_receive(:entity_name).and_return('foo')
    entity_check.should_receive(:name).twice.and_return('ping')

    failing_checks.should_receive(:all).and_return([entity_check])
    Flapjack::Data::Check.should_receive(:intersect).with(:state =>
      ['critical', 'warning', 'unknown']).and_return(failing_checks)

    get '/checks_failing'
    last_response.should be_ok
  end

  it "shows a page listing flapjack statistics" do
    expect_stats
    expect_check_stats
    expect_entity_stats

    Flapjack::Data::Check.should_receive(:intersect).with(:state =>
      ['critical', 'warning', 'unknown']).and_return(failing_checks)

    entity_check.should_receive(:entity_name).and_return('foo')

    get '/self_stats'
    last_response.should be_ok
  end

  it "shows the state of a check for an entity" do
    time = Time.now
    Time.should_receive(:now).and_return(time)

    expect_check_stats

    entity_check.should_receive(:state).and_return('ok')
    entity_check.should_receive(:last_update).and_return(time.to_i - (3 * 60 * 60))
    entity_check.should_receive(:summary).and_return('all good')
    entity_check.should_receive(:details).and_return('seriously, all very wonderful')

    failing_state = double(Flapjack::Data::CheckState, :state => 'critical', :timestamp => time - ((3 * 60 * 60) + (5 * 60)), :summary => 'N')
    last_failing = double('last_failing', :last => failing_state)
    ok_state = double(Flapjack::Data::CheckState, :state => 'ok', :timestamp => time - ((3 * 60 * 60)), :summary => 'Y')
    last_ok = double('last_ok', :last => ok_state)
    no_last = double('no_last', :last => nil)

    states = double('states')
    states.should_receive(:intersect).with(:state => 'ok', :notified => true).
      and_return(last_ok)
    states.should_receive(:intersect).with(:state => 'critical', :notified => true).
      and_return(last_failing)
    states.should_receive(:intersect).with(:state => 'warning', :notified => true).
      and_return(no_last)
    states.should_receive(:intersect).with(:state => 'unknown', :notified => true).
      and_return(no_last)
    states.should_receive(:intersect).with(:state => 'acknowledgement', :notified => true).
      and_return(no_last)
    states.should_receive(:last).and_return(ok_state)

    entity_check.should_receive(:states).twice.and_return(states)

    no_sched_maint = double('no_sched_maint', :all => [])
    entity_check.should_receive(:scheduled_maintenances_by_start).and_return(no_sched_maint)

    entity_check.should_receive(:failed?).and_return(false)

    entity_check.should_receive(:scheduled_maintenance_at).with(time).and_return(nil)
    entity_check.should_receive(:unscheduled_maintenance_at).with(time).and_return(nil)

    no_contacts = double('no_contacts', :all => [])
    entity_check.should_receive(:contacts).and_return(no_contacts)

    all_states = double('all_states', :all => [ok_state, failing_state])
    states.should_receive(:intersect_range).
      with(nil, time.to_i, :order => 'desc', :limit => 20, :by_score => true).
      and_return(all_states)

    entity_check.should_receive(:enabled).and_return(true)

    Flapjack::Data::Check.should_receive(:intersect).with(:state =>
      ['critical', 'warning', 'unknown']).and_return(failing_checks)

    all_checks = double('no_checks', :all => [entity_check])
    Flapjack::Data::Check.should_receive(:intersect).
      with(:entity_name => entity_name_esc, :name => 'ping').and_return(all_checks)

    get "/check?entity=#{entity_name_esc}&check=ping"
    last_response.should be_ok
    # TODO test instance variables set to appropriate values
  end

  it "returns 404 if an unknown entity/check is requested" do
    no_checks = double('no_checks', :all => [])
    Flapjack::Data::Check.should_receive(:intersect).
      with(:entity_name => entity_name_esc, :name => 'ping').and_return(no_checks)

    get "/check?entity=#{entity_name_esc}&check=ping"
    last_response.should be_not_found
  end

  it "creates an acknowledgement for an entity check" do
    all_entity_checks = double('all_entity_checks', :all => [entity_check])
    Flapjack::Data::Check.should_receive(:intersect).
      with(:entity_name => entity_name, :name => 'ping').and_return(all_entity_checks)

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

    all_entity_checks = double('all_entity_checks', :all => [entity_check])
    Flapjack::Data::Check.should_receive(:intersect).
      with(:entity_name => entity_name_esc, :name => 'ping').and_return(all_entity_checks)

    sched_maint = double(Flapjack::Data::ScheduledMaintenance)
    sched_maint.should_receive(:save).and_return(true)
    Flapjack::Data::ScheduledMaintenance.should_receive(:new).
      with(:start_time => start_time.to_i,
           :end_time => start_time.to_i + duration,
           :summary => summary).and_return(sched_maint)

    entity_check.should_receive(:add_scheduled_maintenance).
      with(sched_maint)

    post "/scheduled_maintenances/#{entity_name_esc}/ping?"+
      "start_time=1+day+ago&duration=30+minutes&summary=wow"

    last_response.status.should == 302
  end

  it "deletes a scheduled maintenance period for an entity check" do
    t = Time.now.to_i

    start_time = t - (24 * 60 * 60)

    all_entity_checks = double('all_entity_checks', :all => [entity_check])
    Flapjack::Data::Check.should_receive(:intersect).
      with(:entity_name => entity_name_esc, :name => 'ping').and_return(all_entity_checks)

    sched_maint = double(Flapjack::Data::ScheduledMaintenance)
    first_sched_maint = double('first_sched_maint', :first => sched_maint)
    sched_maints = double('sched_maints')
    sched_maints.should_receive(:intersect_range).with(start_time, start_time,
      :by_score => true).and_return(first_sched_maint)
    entity_check.should_receive(:scheduled_maintenances_by_start).and_return(sched_maints)
    entity_check.should_receive(:end_scheduled_maintenance).with(sched_maint, an_instance_of(Time))

    delete "/scheduled_maintenances/#{entity_name_esc}/ping?start_time=#{start_time}"
    last_response.status.should == 302
  end

  it "shows a list of all known contacts" do
    Flapjack::Data::Contact.should_receive(:all).and_return([])

    get "/contacts"
    last_response.should be_ok
  end

  it "shows details of an individual contact found by id" do
    contact = double('contact')
    contact.should_receive(:name).twice.and_return("Smithson Smith")

    no_checks = double('no_checks', :all => [])

    medium = double(Flapjack::Data::Medium)
    medium.should_receive(:alerting_checks).and_return(no_checks)
    medium.should_receive(:type).twice.and_return('sms')
    medium.should_receive(:address).and_return('0123456789')
    medium.should_receive(:interval).twice.and_return(60)
    medium.should_receive(:rollup_threshold).and_return(10)

    all_media = double('all_media', :all => [medium])
    contact.should_receive(:media).and_return(all_media)

    no_notification_rules = double('no_notification_rules', :all => [])
    contact.should_receive(:notification_rules).and_return(no_notification_rules)

    no_entities = double('no_entities', :all => [])
    contact.should_receive(:entities).and_return(no_entities)

    Flapjack::Data::Contact.should_receive(:find_by_id).
      with('0362').and_return(contact)

    get "/contacts/0362"
    last_response.should be_ok
  end

end
