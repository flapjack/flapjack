require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::UnscheduledMaintenances', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:unscheduled_maintenance) { double(Flapjack::Data::UnscheduledMaintenance,
    :id => unscheduled_maintenance_data[:id]) }
  let(:unscheduled_maintenance_2) { double(Flapjack::Data::UnscheduledMaintenance,
    :id => unscheduled_maintenance_2_data[:id]) }

  let(:check) { double(Flapjack::Data::Check, :id => check_data[:id]) }

  it "creates an unscheduled maintenance period" do
    expect(Flapjack::Data::UnscheduledMaintenance).to receive(:lock).with(no_args).and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::UnscheduledMaintenance).to receive(:intersect).
      with(:id => [unscheduled_maintenance_data[:id]]).
      and_return(empty_ids)

    expect(unscheduled_maintenance).to receive(:invalid?).and_return(false)
    expect(unscheduled_maintenance).to receive(:save).and_return(true)
    expect(Flapjack::Data::UnscheduledMaintenance).to receive(:new).with(unscheduled_maintenance_data).
      and_return(unscheduled_maintenance)

    expect(unscheduled_maintenance).to receive(:as_json).
      with(:only => an_instance_of(Array)).and_return(unscheduled_maintenance_data)

    expect(Flapjack::Data::UnscheduledMaintenance).to receive(:jsonapi_type).and_return('unscheduled_maintenance')

    post "/unscheduled_maintenances", Flapjack.dump_json(:data => {:unscheduled_maintenances => unscheduled_maintenance_data.merge(:type => 'unscheduled_maintenance')}), jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data => {
      :unscheduled_maintenances => unscheduled_maintenance_data.merge(
        :type => 'unscheduled_maintenance',
        :links => {:self  => "http://example.org/unscheduled_maintenances/#{unscheduled_maintenance.id}",
                   :check => "http://example.org/unscheduled_maintenances/#{unscheduled_maintenance.id}/check"})
    }))
  end

  it 'returns a single unscheduled maintenance period' do
    expect(Flapjack::Data::UnscheduledMaintenance).to receive(:find_by_id!).
      with(unscheduled_maintenance.id).and_return(unscheduled_maintenance)

    expect(unscheduled_maintenance).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(unscheduled_maintenance_data)

    get "/unscheduled_maintenances/#{unscheduled_maintenance.id}"
    expect(last_response).to be_ok

    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data => {
      :unscheduled_maintenances => unscheduled_maintenance_data.merge(
        :type => 'unscheduled_maintenance',
        :links => {:self  => "http://example.org/unscheduled_maintenances/#{unscheduled_maintenance.id}",
                   :check => "http://example.org/unscheduled_maintenances/#{unscheduled_maintenance.id}/check"})
    }))
  end

  it 'returns multiple unscheduled_maintenance periods' do
    sorted = double('sorted')
    expect(sorted).to receive(:find_by_ids!).
      with(unscheduled_maintenance.id, unscheduled_maintenance_2.id).
      and_return([unscheduled_maintenance, unscheduled_maintenance_2])
    expect(Flapjack::Data::UnscheduledMaintenance).to receive(:sort).
      with(:timestamp).and_return(sorted)

    expect(unscheduled_maintenance).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(unscheduled_maintenance_data)

    expect(unscheduled_maintenance_2).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(unscheduled_maintenance_2_data)

    get "/unscheduled_maintenances/#{unscheduled_maintenance.id},#{unscheduled_maintenance_2.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data => {
      :unscheduled_maintenances => [
        unscheduled_maintenance_data.merge(
          :type => 'unscheduled_maintenance',
          :links => {:self  => "http://example.org/unscheduled_maintenances/#{unscheduled_maintenance.id}",
                     :check => "http://example.org/unscheduled_maintenances/#{unscheduled_maintenance.id}/check"}),
        unscheduled_maintenance_2_data.merge(
          :type => 'unscheduled_maintenance',
          :links => {:self  => "http://example.org/unscheduled_maintenances/#{unscheduled_maintenance_2.id}",
                     :check => "http://example.org/unscheduled_maintenances/#{unscheduled_maintenance_2.id}/check"})]
    }))
  end

  it 'returns paginated unscheduled maintenance periods' do
    meta = {
      :pagination => {
        :page        => 1,
        :per_page    => 20,
        :total_pages => 1,
        :total_count => 1
      }
    }

    expect(Flapjack::Data::UnscheduledMaintenance).to receive(:count).and_return(1)

    page = double('page', :all => [unscheduled_maintenance])
    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).
      and_return(page)
    expect(Flapjack::Data::UnscheduledMaintenance).to receive(:sort).
      with(:timestamp).and_return(sorted)

    expect(unscheduled_maintenance).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(unscheduled_maintenance_data)

    get '/unscheduled_maintenances'
    expect(last_response).to be_ok
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data => {
      :unscheduled_maintenances => [
        unscheduled_maintenance_data.merge(
          :type => 'unscheduled_maintenance',
          :links => {:self  => "http://example.org/unscheduled_maintenances/#{unscheduled_maintenance.id}",
                     :check => "http://example.org/unscheduled_maintenances/#{unscheduled_maintenance.id}/check"})]
    }, :meta => meta))
  end

  it "ends an unscheduled maintenance period for a check" do
    end_time = Time.now + (60 * 60)

    expect(Flapjack::Data::UnscheduledMaintenance).to receive(:find_by_ids!).
    with(unscheduled_maintenance.id).and_return([unscheduled_maintenance])

    expect(unscheduled_maintenance).to receive(:end_time=).with(end_time.to_i)
    expect(unscheduled_maintenance).to receive(:invalid?).and_return(false)
    expect(unscheduled_maintenance).to receive(:save).and_return(true)

    put "/unscheduled_maintenances/#{unscheduled_maintenance.id}",
      Flapjack.dump_json(:data => {:unscheduled_maintenances => {:id => unscheduled_maintenance.id, :type => 'unscheduled_maintenance', :end_time => end_time.to_i}}),
      jsonapi_put_env
    expect(last_response.status).to eq(204)
  end

end
