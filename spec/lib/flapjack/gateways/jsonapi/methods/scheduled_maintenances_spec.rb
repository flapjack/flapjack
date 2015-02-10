require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::ScheduledMaintenances', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:scheduled_maintenance) { double(Flapjack::Data::ScheduledMaintenance, :id => scheduled_maintenance_data[:id]) }
  let(:scheduled_maintenance_2) { double(Flapjack::Data::ScheduledMaintenance,
      :id => scheduled_maintenance_2_data[:id]) }

  let(:check) { double(Flapjack::Data::Check, :id => check_data[:id]) }

  it "creates a scheduled maintenance period" do
    expect(Flapjack::Data::ScheduledMaintenance).to receive(:lock).with(Flapjack::Data::Check).and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    full_ids = double('full_ids')
    expect(full_ids).to receive(:associated_ids_for).with(:check_by_start).
      and_return({scheduled_maintenance.id => nil})
    expect(Flapjack::Data::ScheduledMaintenance).to receive(:intersect).
      with(:id => [scheduled_maintenance_data[:id]]).twice.
      and_return(empty_ids, full_ids)

    expect(scheduled_maintenance).to receive(:invalid?).and_return(false)
    expect(scheduled_maintenance).to receive(:save).and_return(true)
    expect(Flapjack::Data::ScheduledMaintenance).to receive(:new).with(scheduled_maintenance_data).
      and_return(scheduled_maintenance)

    expect(scheduled_maintenance).to receive(:as_json).
      with(:only => an_instance_of(Array)).and_return(scheduled_maintenance_data)

    post "/scheduled_maintenances", Flapjack.dump_json(:scheduled_maintenances => scheduled_maintenance_data), jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json(:scheduled_maintenances => scheduled_maintenance_data.merge(:links => {
      :check => nil
    })))
  end

  it "doesn't create a scheduled maintenance period if the start time isn't passed" do
    expect(Flapjack::Data::ScheduledMaintenance).to receive(:lock).with(Flapjack::Data::Check).and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::ScheduledMaintenance).to receive(:intersect).
      with(:id => [scheduled_maintenance_data[:id]]).and_return(empty_ids)

    errors = double('errors', :full_messages => ['err'])
    expect(scheduled_maintenance).to receive(:errors).and_return(errors)

    bad_data = scheduled_maintenance_data.reject {|k| k.eql?(:start_time) }

    expect(scheduled_maintenance).to receive(:invalid?).and_return(true)
    expect(scheduled_maintenance).not_to receive(:save)
    expect(Flapjack::Data::ScheduledMaintenance).to receive(:new).with(bad_data).
      and_return(scheduled_maintenance)

    post "/scheduled_maintenances", Flapjack.dump_json(:scheduled_maintenances => bad_data), jsonapi_post_env
    expect(last_response.status).to eq(403)
    # TODO body error message
  end

  it "creates a scheduled maintenance period linked to a check" do
    expect(Flapjack::Data::ScheduledMaintenance).to receive(:lock).with(Flapjack::Data::Check).and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    full_ids = double('full_ids')
    expect(full_ids).to receive(:associated_ids_for).with(:check_by_start).
      and_return({scheduled_maintenance.id => check.id})
    expect(Flapjack::Data::ScheduledMaintenance).to receive(:intersect).
      with(:id => [scheduled_maintenance_data[:id]]).twice.
      and_return(empty_ids, full_ids)

    expect(Flapjack::Data::Check).to receive(:find_by_id!).with(check.id).
      and_return(check)

    expect(scheduled_maintenance).to receive(:invalid?).and_return(false)
    expect(scheduled_maintenance).to receive(:save).and_return(true)
    expect(scheduled_maintenance).to receive(:check=).with(check)
    expect(Flapjack::Data::ScheduledMaintenance).to receive(:new).with(scheduled_maintenance_data).
      and_return(scheduled_maintenance)

    expect(scheduled_maintenance).to receive(:as_json).
      with(:only => an_instance_of(Array)).and_return(scheduled_maintenance_data)

    post "/scheduled_maintenances", Flapjack.dump_json(:scheduled_maintenances => scheduled_maintenance_data.merge(:links => {
      :check => check.id
    })), jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json(:links => {
        'scheduled_maintenances.check' => 'http://example.org/checks/{scheduled_maintenances.check}',
      },
      :scheduled_maintenances => scheduled_maintenance_data.merge(:links => {
        :check => check.id
      }
    )))
  end

  it 'returns a single scheduled maintenance period' do
    expect(Flapjack::Data::ScheduledMaintenance).to receive(:find_by_id!).
      with(scheduled_maintenance.id).and_return(scheduled_maintenance)

    full_ids = double('full_ids')
    expect(full_ids).to receive(:associated_ids_for).with(:check_by_start).and_return({scheduled_maintenance.id => nil})
    expect(Flapjack::Data::ScheduledMaintenance).to receive(:intersect).
      with(:id => [scheduled_maintenance.id]).and_return(full_ids)

    expect(scheduled_maintenance).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(scheduled_maintenance_data)

    get "/scheduled_maintenances/#{scheduled_maintenance.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:scheduled_maintenances => scheduled_maintenance_data.merge(:links => {
        :check => nil
    })))
  end

  it 'returns multiple scheduled_maintenance periods' do
    sorted = double('sorted')
    expect(sorted).to receive(:find_by_ids!).
      with(scheduled_maintenance.id, scheduled_maintenance_2.id).
      and_return([scheduled_maintenance, scheduled_maintenance_2])
    expect(Flapjack::Data::ScheduledMaintenance).to receive(:sort).
      with(:timestamp).and_return(sorted)

    full_ids = double('full_ids')
    expect(full_ids).to receive(:associated_ids_for).with(:check_by_start).
      and_return({scheduled_maintenance.id => nil, scheduled_maintenance_2.id => nil})
    expect(Flapjack::Data::ScheduledMaintenance).to receive(:intersect).
      with(:id => [scheduled_maintenance.id, scheduled_maintenance_2.id]).and_return(full_ids)

    expect(scheduled_maintenance).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(scheduled_maintenance_data)

    expect(scheduled_maintenance_2).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(scheduled_maintenance_2_data)

    get "/scheduled_maintenances/#{scheduled_maintenance.id},#{scheduled_maintenance_2.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:scheduled_maintenances => [
      scheduled_maintenance_data.merge(:links => {:check => nil}),
      scheduled_maintenance_2_data.merge(:links => {:check => nil}),
    ]))
  end

  it 'returns paginated scheduled maintenance periods' do
    meta = {
      :pagination => {
        :page        => 1,
        :per_page    => 20,
        :total_pages => 1,
        :total_count => 1
      }
    }

    expect(Flapjack::Data::ScheduledMaintenance).to receive(:count).and_return(1)

    page = double('page', :all => [scheduled_maintenance])
    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).
      and_return(page)
    expect(Flapjack::Data::ScheduledMaintenance).to receive(:sort).
      with(:timestamp).and_return(sorted)

    full_ids = double('full_ids')
    expect(full_ids).to receive(:associated_ids_for).with(:check_by_start).and_return({scheduled_maintenance.id => nil})
    expect(Flapjack::Data::ScheduledMaintenance).to receive(:intersect).
      with(:id => [scheduled_maintenance.id]).and_return(full_ids)

    expect(scheduled_maintenance).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(scheduled_maintenance_data)

    get '/scheduled_maintenances'
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:scheduled_maintenances => [scheduled_maintenance_data.merge(:links => {
        :check => nil
    })], :meta => meta))
  end

  it "deletes a scheduled maintenance period" do
    scheduled_maintenances = double('scheduled_maintenances')
    expect(scheduled_maintenances).to receive(:ids).and_return([scheduled_maintenance.id])
    expect(scheduled_maintenances).to receive(:destroy_all)
    expect(Flapjack::Data::ScheduledMaintenance).to receive(:intersect).
      with(:id => [scheduled_maintenance.id]).and_return(scheduled_maintenances)

    delete "/scheduled_maintenances/#{scheduled_maintenance.id}"
    expect(last_response.status).to eq(204)
  end

  it "deletes multiple scheduled maintenance periods" do
    scheduled_maintenances = double('scheduled_maintenances')
    expect(scheduled_maintenances).to receive(:ids).and_return([scheduled_maintenance.id, scheduled_maintenance_2.id])
    expect(scheduled_maintenances).to receive(:destroy_all)
    expect(Flapjack::Data::ScheduledMaintenance).to receive(:intersect).
      with(:id => [scheduled_maintenance.id, scheduled_maintenance_2.id]).and_return(scheduled_maintenances)

    delete "/scheduled_maintenances/#{scheduled_maintenance.id},#{scheduled_maintenance_2.id}"
    expect(last_response.status).to eq(204)
  end

  it "does not delete a scheduled maintenance period that's not found" do
    scheduled_maintenances = double('scheduled_maintenances')
    expect(scheduled_maintenances).to receive(:ids).and_return([])
    expect(scheduled_maintenances).not_to receive(:destroy_all)
    expect(Flapjack::Data::ScheduledMaintenance).to receive(:intersect).
      with(:id => [scheduled_maintenance.id]).and_return(scheduled_maintenances)

    delete "/scheduled_maintenances/#{scheduled_maintenance.id}"
    expect(last_response).to be_not_found
  end

end
