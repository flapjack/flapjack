require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::Checks', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:check) { double(Flapjack::Data::Check, :id => check_data[:id]) }
  let(:tag)   { double(Flapjack::Data::Tag, :id => tag_data[:id]) }

  let(:check_presenter) { double(Flapjack::Gateways::JSONAPI::Helpers::CheckPresenter) }

  it "creates a check" do
    expect(Flapjack::Data::Check).to receive(:lock).with(Flapjack::Data::Tag).and_yield
    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Check).to receive(:intersect).
      with(:id => [check_data[:id]]).and_return(empty_ids)

    expect(check).to receive(:invalid?).and_return(false)
    expect(check).to receive(:save).and_return(true)
    expect(Flapjack::Data::Check).to receive(:new).with(check_data).
      and_return(check)

    expect(Flapjack::Data::Check).to receive(:as_jsonapi).with(true, check).and_return(check_data)

    post "/checks", Flapjack.dump_json(:checks => check_data), jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json(:checks => check_data))
  end

  it "creates a check with a linked tag" do
    check_with_tag_data = check_data.merge(:links => {:tags => [tag_data[:id]]})

    expect(Flapjack::Data::Check).to receive(:lock).with(Flapjack::Data::Tag).and_yield
    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Check).to receive(:intersect).
      with(:id => [check_with_tag_data[:id]]).and_return(empty_ids)

    expect(check).to receive(:invalid?).and_return(false)
    expect(check).to receive(:save).and_return(true)
    expect(Flapjack::Data::Check).to receive(:new).with(check_data).
      and_return(check)

    expect(Flapjack::Data::Tag).to receive(:find_by_ids!).with(tag_data[:id]).
      and_return([tag])
    check_tags = double('check_tags')
    expect(check_tags).to receive(:add).with(tag)
    expect(check).to receive(:tags).and_return(check_tags)

    expect(Flapjack::Data::Check).to receive(:as_jsonapi).with(true, check).and_return(check_with_tag_data)

    post "/checks", Flapjack.dump_json(:checks => check_with_tag_data), jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json(:checks => check_with_tag_data))
  end

  it "retrieves paginated checks" do
    meta = {
      :pagination => {
        :page        => 1,
        :per_page    => 20,
        :total_pages => 1,
        :total_count => 1
      }
    }

    expect(Flapjack::Data::Check).to receive(:count).and_return(1)

    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).
      and_return([check])
    expect(Flapjack::Data::Check).to receive(:sort).
      with(:name, :order => 'alpha').and_return(sorted)

    expect(Flapjack::Data::Check).to receive(:as_jsonapi).with(false, check).and_return([check_data])

    get '/checks'
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:checks => [check_data], :meta => meta))
  end

  it "retrieves one check" do
    expect(Flapjack::Data::Check).to receive(:find_by_ids!).
      with(check.id).and_return([check])

    expect(Flapjack::Data::Check).to receive(:as_jsonapi).with(true, check).and_return(check_data)

    get "/checks/#{check.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:checks => check_data))
  end

  it "retrieves several checks" do
    check_2 = double(Flapjack::Data::Check, :id => check_2_data[:id])

    expect(Flapjack::Data::Check).to receive(:find_by_ids!).
      with(check.id, check_2.id).and_return([check, check_2])

    expect(Flapjack::Data::Check).to receive(:as_jsonapi).
      with(false, check, check_2).and_return([check_data, check_2_data])

    get "/checks/#{check.id},#{check_2.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:checks => [check_data, check_2_data]))
  end

  it 'disables a check' do
    expect(Flapjack::Data::Check).to receive(:find_by_ids!).
      with(check.id).and_return([check])

    expect(check).to receive(:enabled=).with(false)
    expect(check).to receive(:invalid?).and_return(false)
    expect(check).to receive(:save).and_return(true)

    put "/checks/#{check.id}",
      Flapjack.dump_json(:checks => {:id => check.id, :enabled => false}),
      jsonapi_put_env
    expect(last_response.status).to eq(204)
  end

  it 'adds a linked tag to a check'

  it 'removes a linked tag from a check'

  it "creates an acknowledgement for a check" # do
  #   expect(Flapjack::Data::Check).to receive(:find_by_ids!).
  #     with(check.id).and_return([check])

  #   expect(Flapjack::Data::Event).to receive(:create_acknowledgements).
  #     with('events', [check], :duration => (4 * 60 * 60))

  #   post "/unscheduled_maintenances/checks/#{check.id}", {}, jsonapi_post_env
  #   expect(last_response.status).to eq(204)
  # end

  it "ends an unscheduled maintenance period for a check" # do
  #   end_time = Time.now + (60 * 60) # an hour from now
  #   expect(check).to receive(:clear_unscheduled_maintenance).with(end_time.to_i)

  #   expect(Flapjack::Data::Check).to receive(:find_by_ids!).
  #     with(check.id).and_return([check])

  #   patch "/unscheduled_maintenances/checks/#{check.id}",
  #     Flapjack.dump_json([{:op => 'replace', :path => '/unscheduled_maintenances/0/end_time', :value => end_time.iso8601}]),
  #     jsonapi_patch_env
  #   expect(last_response.status).to eq(204)
  # end

  it "creates a scheduled maintenance period for a check" # do
  #   start = Time.now + (60 * 60) # an hour from now
  #   duration = (2 * 60 * 60)     # two hours

  #   expect(Flapjack::Data::Check).to receive(:lock).
  #     with(Flapjack::Data::ScheduledMaintenance).and_yield

  #   expect(Flapjack::Data::Check).to receive(:find_by_ids!).
  #     with(check.id).and_return([check])

  #   sched_maint = double(Flapjack::Data::ScheduledMaintenance)
  #   expect(sched_maint).to receive(:invalid?).and_return(false)
  #   expect(sched_maint).to receive(:save).and_return(true)
  #   expect(check).to receive(:add_scheduled_maintenance).with(sched_maint)
  #   expect(Flapjack::Data::ScheduledMaintenance).to receive(:new).
  #     with(:start_time => start.getutc.to_i,
  #          :end_time => start.getutc.to_i + duration,
  #          :summary => 'test').
  #     and_return(sched_maint)

  #   post "/scheduled_maintenances/checks/#{check.id}",
  #     Flapjack.dump_json(:scheduled_maintenances => [{:start_time => start.iso8601, :summary => 'test', :duration => duration}]),
  #     jsonapi_post_env
  #   expect(last_response.status).to eq(204)
  # end

  it "doesn't create a scheduled maintenance period for a check if the start time isn't passed" # do
  #   duration = (2 * 60 * 60)     # two hours

  #   post "/scheduled_maintenances/checks/#{check.id}",
  #     Flapjack.dump_json(:summary => 'test', :duration => duration), jsonapi_post_env
  #   expect(last_response.status).to eq(403)
  # end

  it "deletes a scheduled maintenance period for an entity check" # do
  #   start_time = Time.now + (60 * 60) # an hour from now

  #   sched_maint = double(Flapjack::Data::ScheduledMaintenance)
  #   sched_maints = double('sched_maints', :all => [sched_maint])
  #   sm_range = double('sm_range')
  #   expect(sm_range).to receive(:intersect_range).
  #     with(start_time.to_i, start_time.to_i, :by_score => true).
  #     and_return(sched_maints)

  #   expect(check).to receive(:scheduled_maintenances_by_start).and_return(sm_range)
  #   expect(check).to receive(:end_scheduled_maintenance).with(sched_maint, an_instance_of(Time))

  #   expect(Flapjack::Data::Check).to receive(:find_by_ids!).
  #     with(check.id).and_return([check])

  #   delete "/scheduled_maintenances/checks/#{check.id}",
  #     :start_time => start_time.iso8601
  #   expect(last_response.status).to eq(204)
  # end

  it "doesn't delete a scheduled maintenance period for a check if the start time isn't passed" # do
  #   expect(check).not_to receive(:end_scheduled_maintenance)

  #   delete "/scheduled_maintenances/checks/#{check.id}"
  #   expect(last_response.status).to eq(403)
  # end

  it "deletes scheduled maintenance periods for multiple checks" # do
  #   start_time = Time.now + (60 * 60) # an hour from now

  #   check_2 = double(Flapjack::Data::Check, :id => '9012')

  #   sched_maint = double(Flapjack::Data::ScheduledMaintenance)
  #   sched_maints = double('sched_maints', :all => [sched_maint])
  #   sm_range = double('sm_range')
  #   expect(sm_range).to receive(:intersect_range).
  #     with(start_time.to_i, start_time.to_i, :by_score => true).
  #     and_return(sched_maints)

  #   sched_maint_2 = double(Flapjack::Data::ScheduledMaintenance)
  #   sched_maints_2 = double('sched_maints', :all => [sched_maint_2])
  #   sm_range_2 = double('sm_range')
  #   expect(sm_range_2).to receive(:intersect_range).
  #     with(start_time.to_i, start_time.to_i, :by_score => true).
  #     and_return(sched_maints_2)

  #   expect(check).to receive(:scheduled_maintenances_by_start).and_return(sm_range)
  #   expect(check).to receive(:end_scheduled_maintenance).with(sched_maint, an_instance_of(Time))

  #   expect(check_2).to receive(:scheduled_maintenances_by_start).and_return(sm_range_2)
  #   expect(check_2).to receive(:end_scheduled_maintenance).with(sched_maint_2, an_instance_of(Time))

  #   expect(Flapjack::Data::Check).to receive(:find_by_ids!).
  #     with(check.id, check_2.id).and_return([check, check_2])

  #   delete "/scheduled_maintenances/checks/#{check.id},#{check_2.id}",
  #     :start_time => start_time.iso8601
  #   expect(last_response.status).to eq(204)
  # end

end
