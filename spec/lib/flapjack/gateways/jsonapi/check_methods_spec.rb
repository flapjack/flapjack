require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::CheckMethods', :sinatra => true, :logger => true do

  include_context "jsonapi"

  let(:entity)   { double(Flapjack::Data::Entity, :id => 'efgh') }
  let(:check)    { double(Flapjack::Data::Check, :id => '5678') }

  let(:check_data)   {
    {'id'          => check.id,
     'entity_name' => 'www.example.com',
     'name'        => 'SSH'
    }
   }

  let(:check_presenter) { double(Flapjack::Gateways::JSONAPI::CheckPresenter) }

  it "retrieves all checks" do
    expect(check).to receive(:entity).and_return(entity)
    expect(check).to receive(:as_json).and_return(check_data)
    expect(Flapjack::Data::Check).to receive(:all).and_return([check])

    get '/checks'
    expect(last_response).to be_ok
    expect(last_response.body).to eq({:checks => [check_data]}.to_json)
  end

  it "retrieves one check" do
    expect(check).to receive(:entity).and_return(entity)
    expect(check).to receive(:as_json).and_return(check_data)
    expect(Flapjack::Data::Check).to receive(:find_by_ids!).
      with([check.id]).and_return([check])

    get "/checks/#{check.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq({:checks => [check_data]}.to_json)
  end

  it "retrieves several checks" do
    check_2 = double(Flapjack::Data::Check, :id => 'abcd')
    check_data_2 = {'entity_name' => 'www.example.com', 'name' => 'PING', 'id' => check_2.id}

    expect(check).to receive(:entity).and_return(entity)
    expect(check).to receive(:as_json).and_return(check_data)
    expect(check_2).to receive(:entity).and_return(entity)
    expect(check_2).to receive(:as_json).and_return(check_data_2)
    expect(Flapjack::Data::Check).to receive(:find_by_ids!).
      with([check.id, check_2.id]).and_return([check, check_2])

    get "/checks/#{check.id},#{check_2.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq({:checks => [check_data, check_data_2]}.to_json)
  end

  it 'disables a check' do
    expect(Flapjack::Data::Check).to receive(:find_by_ids!).
      with([check.id]).and_return([check])

    expect(check).to receive(:disable!)

    patch "/checks/#{check.id}",
      [{:op => 'replace', :path => '/checks/0/enabled', :value => false}].to_json,
      jsonapi_patch_env
    expect(last_response.status).to eq(204)
  end

  it "creates an acknowledgement for a check" do
    expect(Flapjack::Data::Check).to receive(:find_by_ids!).
      with([check.id]).and_return([check])

    expect(Flapjack::Data::Event).to receive(:create_acknowledgement).
      with('events', check, :duration => (4 * 60 * 60))

    post "/unscheduled_maintenances/checks/#{check.id}", {}, jsonapi_post_env
    expect(last_response.status).to eq(204)
  end

  it "ends an unscheduled maintenance period for a check" do
    end_time = Time.now + (60 * 60) # an hour from now
    expect(check).to receive(:clear_unscheduled_maintenance).with(end_time.to_i)

    expect(Flapjack::Data::Check).to receive(:find_by_ids!).
      with([check.id]).and_return([check])

    patch "/unscheduled_maintenances/checks/#{check.id}",
      [{:op => 'replace', :path => '/unscheduled_maintenances/0/end_time', :value => end_time.iso8601}].to_json,
      jsonapi_patch_env
    expect(last_response.status).to eq(204)
  end

  it "creates a scheduled maintenance period for a check" do
    start = Time.now + (60 * 60) # an hour from now
    duration = (2 * 60 * 60)     # two hours

    expect(Flapjack::Data::Check).to receive(:lock).
      with(Flapjack::Data::ScheduledMaintenance).and_yield

    expect(Flapjack::Data::Check).to receive(:find_by_ids!).
      with([check.id]).and_return([check])

    sched_maint = double(Flapjack::Data::ScheduledMaintenance)
    expect(sched_maint).to receive(:invalid?).and_return(false)
    expect(sched_maint).to receive(:save).and_return(true)
    expect(check).to receive(:add_scheduled_maintenance).with(sched_maint)
    expect(Flapjack::Data::ScheduledMaintenance).to receive(:new).
      with(:start_time => start.getutc.to_i,
           :end_time => start.getutc.to_i + duration,
           :summary => 'test').
      and_return(sched_maint)

    post "/scheduled_maintenances/checks/#{check.id}",
      {:scheduled_maintenances => [{:start_time => start.iso8601, :summary => 'test', :duration => duration}]}.to_json,
      jsonapi_post_env
    expect(last_response.status).to eq(204)
  end

  it "doesn't create a scheduled maintenance period for a check if the start time isn't passed" do
    duration = (2 * 60 * 60)     # two hours

    post "/scheduled_maintenances/checks/#{check.id}",
      {:summary => 'test', :duration => duration}.to_json, jsonapi_post_env
    expect(last_response.status).to eq(403)
  end

  it "deletes a scheduled maintenance period for an entity check" do
    start_time = Time.now + (60 * 60) # an hour from now

    sched_maint = double(Flapjack::Data::ScheduledMaintenance)
    sched_maints = double('sched_maints', :all => [sched_maint])
    sm_range = double('sm_range')
    expect(sm_range).to receive(:intersect_range).
      with(start_time.to_i, start_time.to_i, :by_score => true).
      and_return(sched_maints)

    expect(check).to receive(:scheduled_maintenances_by_start).and_return(sm_range)
    expect(check).to receive(:end_scheduled_maintenance).with(sched_maint, an_instance_of(Time))

    expect(Flapjack::Data::Check).to receive(:find_by_ids!).
      with([check.id]).and_return([check])

    delete "/scheduled_maintenances/checks/#{check.id}",
      :start_time => start_time.iso8601
    expect(last_response.status).to eq(204)
  end

  it "doesn't delete a scheduled maintenance period for a check if the start time isn't passed" do
    expect(check).not_to receive(:end_scheduled_maintenance)

    delete "/scheduled_maintenances/checks/#{check.id}"
    expect(last_response.status).to eq(403)
  end

  it "deletes scheduled maintenance periods for multiple checks" do
    start_time = Time.now + (60 * 60) # an hour from now

    check_2 = double(Flapjack::Data::Check, :id => '9012')

    sched_maint = double(Flapjack::Data::ScheduledMaintenance)
    sched_maints = double('sched_maints', :all => [sched_maint])
    sm_range = double('sm_range')
    expect(sm_range).to receive(:intersect_range).
      with(start_time.to_i, start_time.to_i, :by_score => true).
      and_return(sched_maints)

    sched_maint_2 = double(Flapjack::Data::ScheduledMaintenance)
    sched_maints_2 = double('sched_maints', :all => [sched_maint_2])
    sm_range_2 = double('sm_range')
    expect(sm_range_2).to receive(:intersect_range).
      with(start_time.to_i, start_time.to_i, :by_score => true).
      and_return(sched_maints_2)

    expect(check).to receive(:scheduled_maintenances_by_start).and_return(sm_range)
    expect(check).to receive(:end_scheduled_maintenance).with(sched_maint, an_instance_of(Time))

    expect(check_2).to receive(:scheduled_maintenances_by_start).and_return(sm_range_2)
    expect(check_2).to receive(:end_scheduled_maintenance).with(sched_maint_2, an_instance_of(Time))

    expect(Flapjack::Data::Check).to receive(:find_by_ids!).
      with([check.id, check_2.id]).and_return([check, check_2])

    delete "/scheduled_maintenances/checks/#{check.id},#{check_2.id}",
      :start_time => start_time.iso8601
    expect(last_response.status).to eq(204)
  end

  it "creates a test notification event for a check" do
    expect(Flapjack::Data::Check).to receive(:find_by_ids!).
      with([check.id]).and_return([check])

    expect(check).to receive(:entity_name).and_return('www.example.com')

    expect(Flapjack::Data::Event).to receive(:test_notifications).
      with('events', check, an_instance_of(Hash))

    post "/test_notifications/checks/#{check.id}"
    expect(last_response.status).to eq(204)
  end

end
