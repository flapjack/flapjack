require 'spec_helper'
require 'flapjack/gateways/web'

describe Flapjack::Gateways::Web, :sinatra => true, :logger => true do

  def app
    Flapjack::Gateways::Web
  end

  let(:check_name)      { 'example.com:ping' }

  let(:check)  { double(Flapjack::Data::Check, :id => SecureRandom.uuid) }
  let(:states) { double('states') }
  let(:state)  { double(Flapjack::Data::State, :id => SecureRandom.uuid) }

  let(:redis)  { double(Redis) }

  before(:all) do
    Flapjack::Gateways::Web.class_eval {
      set :show_exceptions, false
    }
  end

  before(:each) do
    allow(Flapjack).to receive(:redis).and_return(redis)
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

  def expect_check_stats
    enabled = double('enabled', :count => 1)

    expect(Flapjack::Data::Check).to receive(:intersect).
      with(:enabled => true).and_return(enabled)
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
      expect(Flapjack::Data::Check).to receive(:all).and_return([check])
      expect(check).to receive(:states).and_return(states)

      critical_state = double(Flapjack::Data::State)
      expect(critical_state).to receive(:condition).and_return('critical')

      expect(states).to receive(:last).and_return(critical_state)

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
      expect(Flapjack::Data::Check).to receive(:all).and_return([check])
      expect(check).to receive(:states).and_return(states)

      critical_state = double(Flapjack::Data::State)
      expect(critical_state).to receive(:condition).and_return('critical')

      expect(states).to receive(:last).and_return(critical_state)

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

      expect(check).to receive(:name).and_return(check_name)
      expect(Flapjack::Data::Check).to receive(:all).and_return([check])
      expect(Flapjack::Data::Check).to receive(:all).and_return([check])
      expect(check).to receive(:states).twice.and_return(states)

      latest_notifications = double('latest_notifications')
      expect(check).to receive(:latest_notifications).and_return(latest_notifications)
      expect(latest_notifications).to receive(:last).and_return(nil)

      expect(states).to receive(:last).twice.and_return(nil)

      expect(check).to receive(:in_scheduled_maintenance?).and_return(false)
      expect(check).to receive(:in_unscheduled_maintenance?).and_return(false)

      get '/checks'
      expect(last_response).to be_ok
    end

    it "shows a page listing failing checks" do
      expect_check_stats
      expect(Flapjack::Data::Check).to receive(:all).and_return([check])

      expect(check).to receive(:states).and_return(states)
      expect(states).to receive(:last).and_return(nil)

      get '/checks?type=failing'
      expect(last_response).to be_ok
    end

    it "shows a page listing flapjack statistics" do
      expect_stats
      expect_check_stats
      expect(Flapjack::Data::Check).to receive(:all).and_return([check])
      expect(check).to receive(:states).and_return(states)

      critical_state = double(Flapjack::Data::State)
      expect(critical_state).to receive(:condition).and_return('critical')

      expect(states).to receive(:last).and_return(critical_state)

      get '/self_stats'
      expect(last_response).to be_ok
    end

    it "shows the state of a check" do
      time = Time.now
      expect(Time).to receive(:now).and_return(time)

      expect_check_stats
      expect(Flapjack::Data::Check).to receive(:all).and_return([check])

      expect(check).to receive(:name).and_return(check_name)

      failing_entry = double(Flapjack::Data::Entry)
      failing_state = double(Flapjack::Data::State)
      failing_entries = double(:failing_entries, :last => failing_entry)
      failing_time = time - ((3 * 60 * 60) + (5 * 60))
      expect(failing_state).to receive(:timestamp).and_return(failing_time)
      expect(failing_state).to receive(:condition).and_return('critical')
      expect(failing_state).to receive(:entries).and_return(failing_entries)
      expect(failing_entry).to receive(:timestamp).and_return(failing_time)
      expect(failing_entry).to receive(:action).and_return(nil)
      expect(failing_entry).to receive(:condition).and_return('critical')
      expect(failing_entry).to receive(:summary).twice.and_return('BAAAAD')

      ok_entry = double(Flapjack::Data::Entry)
      ok_state = double(Flapjack::Data::State)
      ok_entries = double(:ok_entries, :last => ok_entry)
      ok_time = time - (3 * 60 * 60)
      expect(ok_state).to receive(:timestamp).twice.and_return(ok_time)
      expect(ok_state).to receive(:condition).twice.and_return('ok')
      expect(ok_state).to receive(:entries).and_return(ok_entries)
      expect(ok_entry).to receive(:action).and_return(nil)
      expect(ok_entry).to receive(:condition).twice.and_return('ok')
      expect(ok_entry).to receive(:timestamp).twice.and_return(ok_time)
      expect(ok_entry).to receive(:summary).exactly(3).times.and_return('smile')
      expect(ok_entry).to receive(:details).and_return('seriously, all very wonderful')
      expect(ok_entry).to receive(:perfdata).and_return([{"key" => "foo", "value" => "bar"}])

      states = double('states')

      expect(states).to receive(:last).twice.and_return(ok_state)

      latest_notifications = double('latest_notifications',
        :all => [failing_entry, ok_entry], :last => ok_entry)
      expect(check).to receive(:latest_notifications).twice.and_return(latest_notifications)

      expect(check).to receive(:states).exactly(3).times.and_return(states)

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

      medium = double(Flapjack::Data::Medium)
      expect(medium).to receive(:alerting_checks).and_return([])
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
