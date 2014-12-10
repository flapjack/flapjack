require 'spec_helper'
require 'flapjack/gateways/web'

describe Flapjack::Gateways::Web, :sinatra => true, :logger => true do

  def app
    Flapjack::Gateways::Web
  end

  let(:check_name)      { 'example.com:ping' }

  let(:check)  { double(Flapjack::Data::Check, :id => SecureRandom.uuid) }
  let(:state)  { double(Flapjack::Data::State, :id => SecureRandom.uuid) }

  let(:redis)  { double(Redis) }

  before(:all) do
    Flapjack::Gateways::Web.class_eval {
      set :show_exceptions, false
    }
  end

  before(:each) do
    allow(Flapjack).to receive(:redis).and_return(redis)
    Flapjack::Gateways::Web.instance_variable_set('@logger', @logger)
  end

  def expect_stats
    expect(redis).to receive(:dbsize).and_return(3)
    expect(redis).to receive(:keys).with('executive_instance:*').and_return(["executive_instance:foo-app-01"])
    expect(redis).to receive(:hget).once.and_return(Time.now.to_i - 60)
    expect(redis).to receive(:hgetall).twice.and_return({'all' => '8001', 'ok' => '8002'},
      {'all' => '9001', 'ok' => '9002'})
    expect(redis).to receive(:llen).with('events')
    expect(Flapjack::Data::Check).to receive(:split_by_freshness).and_return({})
  end

  let(:failing_checks) { double('failing_checks') }

  def expect_check_stats
    enabled = double('enabled', :count => 1)

    expect(Flapjack::Data::Check).to receive(:intersect).
      with(:enabled => true).and_return(enabled)

    expect(failing_checks).to receive(:count).and_return(1)
  end

  def expect_check_status(ec)
    time = Time.now.to_i

    last_failing = double('last_failing',
      :last => double(Flapjack::Data::State, :timestamp => time - ((3 * 60 * 60) + (5 * 60))))
    ok_state = double(Flapjack::Data::State, :condition => 'ok', :timestamp => time - ((3 * 60 * 60)))
    last_ok = double('last_ok', :last => ok_state)
    no_last_ack = double('no_last_ack', :last => nil)

    expect(ok_state).to receive(:summary).and_return('happy results are returned')

    states = double('states')
    expect(states).to receive(:intersect).with(:condition => ['critical', 'warning', 'unknown'], :condition_changed => true, :notified => true).
      and_return(last_failing)
    expect(states).to receive(:intersect).with(:condition => ['ok'], :condition_changed => true, :notified => true).
      and_return(last_ok)
    expect(states).to receive(:intersect).with(:condition_changed => true).
      and_return(last_ok)
    expect(states).to receive(:intersect).with(:action => 'acknowledgement', :notified => true).
      and_return(no_last_ack)
    expect(states).to receive(:last).and_return(ok_state)

    expect(ec).to receive(:states).exactly(5).times.and_return(states)

    expect(ec).to receive(:in_scheduled_maintenance?).and_return(false)
    expect(ec).to receive(:in_unscheduled_maintenance?).and_return(false)
  end

  def expect_failing_checks
    states = double('states')
    expect(states).to receive(:associated_ids_for).with(:check).
      and_return(state.id => check.id)
    expect(Flapjack::Data::State).to receive(:intersect).
      with(:id => [state.id],
           :condition => ['critical', 'warning', 'unknown']).
    and_return(states)

    expect(Flapjack::Data::Check).to receive(:associated_ids_for).with(:state).
      and_return(check.id => state.id)
    expect(Flapjack::Data::Check).to receive(:intersect).
      with(:id => [check.id]).and_return(failing_checks)
  end

  # TODO add data, test that pages contain representations of it
  # (for the methods that access redis directly)

  context "web page design" do

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
      expect_failing_checks

      logo_image_tag = '<img alt="Flapjack" class="logo" src="http://example.org/img/branding.png">'

      get '/self_stats'

      expect( last_response.body ).to include(logo_image_tag)
    end

    it "displays the standard logo if no custom logo configured" do
      Flapjack::Gateways::Web.instance_variable_set('@config', {})
      Flapjack::Gateways::Web.start
      # NOTE Reuse enough of the stats specs to be able to build a page quickly
      expect_stats
      expect_check_stats
      expect_failing_checks

      logo_image_tag = '<img alt="Flapjack" class="logo" src="http://example.org/img/flapjack-2013-notext-transparent-300-300.png">'

      get '/self_stats'

      expect( last_response.body ).to include(logo_image_tag)
    end
  end

  context 'web page behaviour' do

    before(:each) do
      Flapjack::Gateways::Web.instance_variable_set('@config', {})
      Flapjack::Gateways::Web.start
    end

    it "shows a page listing all checks" do
      expect_check_stats
      expect_check_status(check)

      expect(check).to receive(:name).and_return(check_name)
      expect(Flapjack::Data::Check).to receive(:all).and_return([check])
      expect_failing_checks

      get '/checks'
      expect(last_response).to be_ok
    end

    it "shows a page listing failing checks" do
      expect_check_stats
      expect_check_status(check)
      expect_failing_checks

      expect(check).to receive(:name).and_return(check_name)
      expect(failing_checks).to receive(:all).and_return([check])

      get '/checks?type=failing'
      expect(last_response).to be_ok
    end

    it "shows a page listing flapjack statistics" do
      expect_stats
      expect_check_stats
      expect_failing_checks

      get '/self_stats'
      expect(last_response).to be_ok
    end

    it "shows the state of a check" do
      time = Time.now
      expect(Time).to receive(:now).and_return(time)

      expect_check_stats
      expect_failing_checks

      expect(check).to receive(:name).and_return(check_name)

      failing_state = double(Flapjack::Data::State, :condition => 'critical', :timestamp => time - ((3 * 60 * 60) + (5 * 60)))
      expect(failing_state).to receive(:summary).twice.and_return('BAAAAD')
      last_failing = double('last_failing', :last => failing_state)

      ok_state = double(Flapjack::Data::State, :condition => 'ok', :timestamp => time - ((3 * 60 * 60)))
      expect(ok_state).to receive(:summary).exactly(3).times.and_return('smile')
      expect(ok_state).to receive(:details).and_return('seriously, all very wonderful')
      expect(ok_state).to receive(:perfdata).and_return([{"key" => "foo", "value" => "bar"}])
      last_ok = double('last_ok', :last => ok_state)

      no_last = double('no_last', :last => nil)

      states = double('states')

      expect(states).to receive(:intersect).with(:condition_changed => true).and_return(last_ok)

      expect(states).to receive(:intersect).with(:condition => 'ok', :condition_changed => true, :notified => true).
        and_return(last_ok)
      expect(states).to receive(:intersect).with(:condition => 'critical', :condition_changed => true, :notified => true).
        and_return(last_failing)
      expect(states).to receive(:intersect).with(:condition => 'warning', :condition_changed => true, :notified => true).
        and_return(no_last)
      expect(states).to receive(:intersect).with(:condition => 'unknown', :condition_changed => true, :notified => true).
        and_return(no_last)
      expect(states).to receive(:intersect).with(:action => 'acknowledgement', :notified => true).
        and_return(no_last)
      expect(states).to receive(:last).and_return(ok_state)

      expect(check).to receive(:states).exactly(8).times.and_return(states)

      no_sched_maint = double('no_sched_maint', :all => [])
      expect(check).to receive(:scheduled_maintenances_by_start).and_return(no_sched_maint)

      expect(check).to receive(:scheduled_maintenance_at).with(time).and_return(nil)
      expect(check).to receive(:unscheduled_maintenance_at).with(time).and_return(nil)

      all_states = double('all_states', :all => [ok_state, failing_state])
      expect(states).to receive(:intersect_range).
        with(nil, time.to_i, :desc => true, :limit => 20, :by_score => true).
        and_return(all_states)

      expect(check).to receive(:enabled).and_return(true)

      expect(Flapjack::Data::Check).to receive(:find_by_id).with(check.id).
        and_return(check)

      expect(Flapjack::Data::Contact).to receive(:lock).
        with(Flapjack::Data::Medium, Flapjack::Data::Rule).and_yield

      expect(check).to receive(:rule_ids_by_contact_id).and_return({})

      get "/checks/#{check.id}"
      expect(last_response).to be_ok
      # TODO test instance variables set to appropriate values
    end

    it "returns 404 if an unknown check is requested" do
      expect(Flapjack::Data::Check).to receive(:find_by_id).with(check.id).
        and_return(nil)

      get "/checks/#{check.id}"
      expect(last_response).to be_not_found
    end

    it "creates an acknowledgement for a check" do
      expect(Flapjack::Data::Check).to receive(:find_by_id).with(check.id).
        and_return(check)

      expect(Flapjack::Data::Event).to receive(:create_acknowledgements).
        with('events', [check], :summary => "", :duration => (4 * 60 * 60),
             :acknowledgement_id => '1234')

      post "/unscheduled_maintenances/checks/#{check.id}?acknowledgement_id=1234"
      expect(last_response.status).to eq(302)
    end

    it "creates a scheduled maintenance period for a check" do
      t = Time.now.to_i

      start_time = Time.at(t - (24 * 60 * 60))
      duration = 30 * 60
      summary = 'wow'

      expect(Chronic).to receive(:parse).with('1 day ago').and_return(start_time)
      expect(ChronicDuration).to receive(:parse).with('30 minutes').and_return(duration)

      expect(Flapjack::Data::Check).to receive(:find_by_id).with(check.id).
        and_return(check)

      sched_maint = double(Flapjack::Data::ScheduledMaintenance)
      expect(sched_maint).to receive(:save).and_return(true)
      expect(Flapjack::Data::ScheduledMaintenance).to receive(:new).
        with(:start_time => start_time.to_i,
             :end_time => start_time.to_i + duration,
             :summary => summary).and_return(sched_maint)

      expect(check).to receive(:add_scheduled_maintenance).
        with(sched_maint)

      post "/scheduled_maintenances/checks/#{check.id}?"+
        "start_time=1+day+ago&duration=30+minutes&summary=wow"

      expect(last_response.status).to eq(302)
    end

    it "deletes a scheduled maintenance period for a check" do
      t = Time.now.to_i

      start_time = t - (24 * 60 * 60)

      expect(Flapjack::Data::Check).to receive(:find_by_id).with(check.id).
        and_return(check)

      sched_maint = double(Flapjack::Data::ScheduledMaintenance)
      all_sched_maints = double('all_sched_maints', :all => [sched_maint])
      sched_maints = double('sched_maints')
      expect(sched_maints).to receive(:intersect_range).with(start_time, start_time,
        :by_score => true).and_return(all_sched_maints)
      expect(check).to receive(:scheduled_maintenances_by_start).and_return(sched_maints)
      expect(check).to receive(:end_scheduled_maintenance).with(sched_maint, an_instance_of(Time))

      delete "/scheduled_maintenances/checks/#{check.id}?start_time=#{Time.at(start_time).iso8601}"
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
      expect(medium).to receive(:transport).twice.and_return('sms')
      expect(medium).to receive(:address).and_return('0123456789')
      expect(medium).to receive(:interval).twice.and_return(60)
      expect(medium).to receive(:rollup_threshold).and_return(10)

      all_media = double('all_media', :all => [medium])
      expect(contact).to receive(:media).and_return(all_media)

      no_notification_rules = double('no_notification_rules', :all => [])
      expect(contact).to receive(:notification_rules).and_return(no_notification_rules)

      no_checks = double('no_checks', :all => [])
      expect(contact).to receive(:checks).and_return(no_checks)

      expect(Flapjack::Data::Contact).to receive(:find_by_id).
        with('0362').and_return(contact)

      get "/contacts/0362"
      expect(last_response).to be_ok
    end
  end
end
