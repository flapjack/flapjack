require 'spec_helper'
require 'flapjack/gateways/web'

describe Flapjack::Gateways::Web, :sinatra => true, :logger => true do

  def app
    Flapjack::Gateways::Web
  end

  let(:entity_name)     { 'example.com'}
  let(:entity_name_esc) { CGI.escape(entity_name) }
  let(:check)           { 'ping' }

  let(:entity) { double(Flapjack::Data::Entity) }
  let(:check)  { double(Flapjack::Data::Check) }

  let(:redis)  { double(Redis) }

  before(:all) do
    Flapjack::Gateways::Web.class_eval {
      set :show_exceptions, false
    }
  end

  before(:each) do
    allow(Flapjack).to receive(:redis).and_return(redis)
    Flapjack::Gateways::Web.instance_variable_set('@config', {})
    Flapjack::Gateways::Web.instance_variable_set('@logger', @logger)
    Flapjack::Gateways::Web.start
  end

  def expect_stats
    expect(redis).to receive(:dbsize).and_return(3)
    expect(redis).to receive(:keys).with('executive_instance:*').and_return(["executive_instance:foo-app-01"])
    expect(redis).to receive(:hget).once.and_return(Time.now.to_i - 60)
    expect(redis).to receive(:hgetall).twice.and_return({'all' => '8001', 'ok' => '8002'},
      {'all' => '9001', 'ok' => '9002'})
    expect(redis).to receive(:llen).with('events')
    # redis.should_receive(:zrange).with('current_entities', 0, -1).and_return(['foo-app-01.example.com'])
    # redis.should_receive(:zrange).with('current_checks:foo-app-01.example.com', 0, -1, :withscores => true).and_return([['ping', 1382329923.0]])
  end

  let(:failing_checks) { double('failing_checks') }

  def expect_check_stats
    expect(Flapjack::Data::Check).to receive(:count).and_return(1)

    expect(failing_checks).to receive(:count).and_return(1)
  end

  def expect_entity_stats
    enabled_count = double('enabled_count', :count => 1)
    expect(Flapjack::Data::Entity).to receive(:intersect).with(:enabled =>
      true).and_return(enabled_count)

    # entity.should_receive(:name).and_return('foo.example.com')

    failing_enabled = double('failing_enabled', :all => [check])
    expect(failing_checks).to receive(:intersect).with(:enabled => true).
      and_return(failing_enabled)
  end

  def expect_check_status(ec)
    time = Time.now.to_i

    expect(ec).to receive(:state).and_return('ok')
    expect(ec).to receive(:summary).and_return('happy results are returned')
    expect(ec).to receive(:last_update).and_return(time - (3 * 60 * 60))

    last_failing = double('last_failing',
      :last => double(Flapjack::Data::CheckState, :timestamp => time - ((3 * 60 * 60) + (5 * 60))))
    ok_state = double(Flapjack::Data::CheckState, :timestamp => time - ((3 * 60 * 60)))
    last_ok = double('last_ok', :last => ok_state)
    no_last_ack = double('no_last_ack', :last => nil)

    states = double('states')
    expect(states).to receive(:intersect).with(:state => ['critical', 'warning', 'unknown'], :notified => true).
      and_return(last_failing)
    expect(states).to receive(:intersect).with(:state => 'ok', :notified => true).
      and_return(last_ok)
    expect(states).to receive(:intersect).with(:state => 'acknowledgement', :notified => true).
      and_return(no_last_ack)
    expect(states).to receive(:last).and_return(ok_state)

    expect(ec).to receive(:states).exactly(4).times.and_return(states)

    expect(ec).to receive(:in_scheduled_maintenance?).and_return(false)
    expect(ec).to receive(:in_unscheduled_maintenance?).and_return(false)
  end

  # TODO add data, test that pages contain representations of it
  # (for the methods that access redis directly)

  it "shows a page listing all checks" do
    expect_check_stats

    expect_check_status(check)

    expect(check).to receive(:entity_name).and_return('foo')
    expect(check).to receive(:name).twice.and_return('ping')
    expect(Flapjack::Data::Check).to receive(:all).and_return([check])

    expect(Flapjack::Data::Check).to receive(:intersect).
      with(:state => ['critical', 'warning', 'unknown']).
      and_return(failing_checks)

    get '/checks_all'
    expect(last_response).to be_ok
  end

  it "shows a page listing failing checks" do
    expect_check_stats

    expect_check_status(check)

    expect(check).to receive(:entity_name).and_return('foo')
    expect(check).to receive(:name).twice.and_return('ping')

    expect(failing_checks).to receive(:all).and_return([check])
    expect(Flapjack::Data::Check).to receive(:intersect).with(:state =>
      ['critical', 'warning', 'unknown']).and_return(failing_checks)

    get '/checks_failing'
    expect(last_response).to be_ok
  end

  it "shows a page listing flapjack statistics" do
    expect_stats
    expect_check_stats
    expect_entity_stats

    expect(Flapjack::Data::Check).to receive(:intersect).with(:state =>
      ['critical', 'warning', 'unknown']).and_return(failing_checks)

    no_checks = double('no_checks', :all => [])
    expect(Flapjack::Data::Check).to receive(:intersect).with(:enabled => true).
      and_return(no_checks)


    expect(check).to receive(:entity_name).and_return('foo')

    get '/self_stats'
    expect(last_response).to be_ok
  end

  it "shows the state of a check for an entity" do
    time = Time.now
    expect(Time).to receive(:now).and_return(time)

    expect_check_stats

    expect(check).to receive(:state).and_return('ok')
    expect(check).to receive(:last_update).and_return(time.to_i - (3 * 60 * 60))
    expect(check).to receive(:summary).and_return('all good')
    expect(check).to receive(:details).and_return('seriously, all very wonderful')

    failing_state = double(Flapjack::Data::CheckState, :state => 'critical', :timestamp => time - ((3 * 60 * 60) + (5 * 60)), :summary => 'N')
    last_failing = double('last_failing', :last => failing_state)
    ok_state = double(Flapjack::Data::CheckState, :state => 'ok', :timestamp => time - ((3 * 60 * 60)), :summary => 'Y')
    last_ok = double('last_ok', :last => ok_state)
    no_last = double('no_last', :last => nil)

    states = double('states')
    expect(states).to receive(:intersect).with(:state => 'ok', :notified => true).
      and_return(last_ok)
    expect(states).to receive(:intersect).with(:state => 'critical', :notified => true).
      and_return(last_failing)
    expect(states).to receive(:intersect).with(:state => 'warning', :notified => true).
      and_return(no_last)
    expect(states).to receive(:intersect).with(:state => 'unknown', :notified => true).
      and_return(no_last)
    expect(states).to receive(:intersect).with(:state => 'acknowledgement', :notified => true).
      and_return(no_last)
    expect(states).to receive(:last).and_return(ok_state)

    expect(check).to receive(:states).twice.and_return(states)

    no_sched_maint = double('no_sched_maint', :all => [])
    expect(check).to receive(:scheduled_maintenances_by_start).and_return(no_sched_maint)

    expect(check).to receive(:failed?).and_return(false)

    expect(check).to receive(:scheduled_maintenance_at).with(time).and_return(nil)
    expect(check).to receive(:unscheduled_maintenance_at).with(time).and_return(nil)

    no_contacts = double('no_contacts', :all => [])
    expect(check).to receive(:contacts).and_return(no_contacts)

    all_states = double('all_states', :all => [ok_state, failing_state])
    expect(states).to receive(:intersect_range).
      with(nil, time.to_i, :order => 'desc', :limit => 20, :by_score => true).
      and_return(all_states)

    expect(check).to receive(:enabled).and_return(true)

    expect(Flapjack::Data::Check).to receive(:intersect).with(:state =>
      ['critical', 'warning', 'unknown']).and_return(failing_checks)

    all_checks = double('no_checks', :all => [check])
    expect(Flapjack::Data::Check).to receive(:intersect).
      with(:entity_name => entity_name_esc, :name => 'ping').and_return(all_checks)

    get "/check?entity=#{entity_name_esc}&check=ping"
    expect(last_response).to be_ok
    # TODO test instance variables set to appropriate values
  end

  it "returns 404 if an unknown entity/check is requested" do
    no_checks = double('no_checks', :all => [])
    expect(Flapjack::Data::Check).to receive(:intersect).
      with(:entity_name => entity_name_esc, :name => 'ping').and_return(no_checks)

    get "/check?entity=#{entity_name_esc}&check=ping"
    expect(last_response).to be_not_found
  end

  it "creates an acknowledgement for an entity check" do
    all_checks = double('all_checks', :all => [check])
    expect(Flapjack::Data::Check).to receive(:intersect).
      with(:entity_name => entity_name, :name => 'ping').and_return(all_checks)

    expect(Flapjack::Data::Event).to receive(:create_acknowledgement).
      with('events', entity_name, 'ping', :summary => "", :duration => (4 * 60 * 60),
           :acknowledgement_id => '1234')

    post "/acknowledgements/#{entity_name_esc}/ping?acknowledgement_id=1234"
    expect(last_response.status).to eq(302)
  end

  it "creates a scheduled maintenance period for an entity check" do
    t = Time.now.to_i

    start_time = Time.at(t - (24 * 60 * 60))
    duration = 30 * 60
    summary = 'wow'

    expect(Chronic).to receive(:parse).with('1 day ago').and_return(start_time)
    expect(ChronicDuration).to receive(:parse).with('30 minutes').and_return(duration)

    all_checks = double('all_checks', :all => [check])
    expect(Flapjack::Data::Check).to receive(:intersect).
      with(:entity_name => entity_name_esc, :name => 'ping').and_return(all_checks)

    sched_maint = double(Flapjack::Data::ScheduledMaintenance)
    expect(sched_maint).to receive(:save).and_return(true)
    expect(Flapjack::Data::ScheduledMaintenance).to receive(:new).
      with(:start_time => start_time.to_i,
           :end_time => start_time.to_i + duration,
           :summary => summary).and_return(sched_maint)

    expect(check).to receive(:add_scheduled_maintenance).
      with(sched_maint)

    post "/scheduled_maintenances/#{entity_name_esc}/ping?"+
      "start_time=1+day+ago&duration=30+minutes&summary=wow"

    expect(last_response.status).to eq(302)
  end

  it "deletes a scheduled maintenance period for an entity check" do
    t = Time.now.to_i

    start_time = t - (24 * 60 * 60)

    all_checks = double('all_checks', :all => [check])
    expect(Flapjack::Data::Check).to receive(:intersect).
      with(:entity_name => entity_name_esc, :name => 'ping').and_return(all_checks)

    sched_maint = double(Flapjack::Data::ScheduledMaintenance)
    first_sched_maint = double('first_sched_maint', :first => sched_maint)
    sched_maints = double('sched_maints')
    expect(sched_maints).to receive(:intersect_range).with(start_time, start_time,
      :by_score => true).and_return(first_sched_maint)
    expect(check).to receive(:scheduled_maintenances_by_start).and_return(sched_maints)
    expect(check).to receive(:end_scheduled_maintenance).with(sched_maint, an_instance_of(Time))

    delete "/scheduled_maintenances/#{entity_name_esc}/ping?start_time=#{start_time}"
    expect(last_response.status).to eq(302)
  end

  it "shows a list of all known contacts" do
    expect(Flapjack::Data::Contact).to receive(:all).and_return([])

    get "/contacts"
    expect(last_response).to be_ok
  end

  it "shows details of an individual contact found by id" do
    contact = double('contact')
    expect(contact).to receive(:name).and_return("Smithson Smith")

    no_checks = double('no_checks', :all => [])

    medium = double(Flapjack::Data::Medium)
    expect(medium).to receive(:alerting_checks).and_return(no_checks)
    expect(medium).to receive(:type).twice.and_return('sms')
    expect(medium).to receive(:address).and_return('0123456789')
    expect(medium).to receive(:interval).twice.and_return(60)
    expect(medium).to receive(:rollup_threshold).and_return(10)

    all_media = double('all_media', :all => [medium])
    expect(contact).to receive(:media).and_return(all_media)

    no_notification_rules = double('no_notification_rules', :all => [])
    expect(contact).to receive(:notification_rules).and_return(no_notification_rules)

    no_entities = double('no_entities', :all => [])
    expect(contact).to receive(:entities).and_return(no_entities)

    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(contact)

    get "/contacts/0362"
    expect(last_response).to be_ok
  end

end
