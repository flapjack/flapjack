require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::UnscheduledMaintenanceLinks', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:unscheduled_maintenance) { double(Flapjack::Data::UnscheduledMaintenance,
                                  :id => unscheduled_maintenance_data[:id]) }
  let(:check) { double(Flapjack::Data::Check, :id => check_data[:id]) }

  it 'shows the check for a unscheduled maintenance period' do
    expect(Flapjack::Data::UnscheduledMaintenance).to receive(:lock).with(Flapjack::Data::Check).and_yield

    expect(unscheduled_maintenance).to receive(:check).and_return(check)

    unscheduled_maintenances = double('unscheduled_maintenances', :all => [unscheduled_maintenance])
    expect(unscheduled_maintenances).to receive(:empty?).and_return(false)
    expect(Flapjack::Data::UnscheduledMaintenance).to receive(:intersect).
      with(:id => unscheduled_maintenance.id).and_return(unscheduled_maintenances)

    get "/unscheduled_maintenances/#{unscheduled_maintenance.id}/check"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => {:type => 'check', :id => check.id},
      :links => {
        :self    => "http://example.org/unscheduled_maintenances/#{unscheduled_maintenance.id}/relationships/check",
        :related => "http://example.org/unscheduled_maintenances/#{unscheduled_maintenance.id}/check",
      }
    ))
  end

  it 'cannot change the check for a unscheduled maintenance period' do
    patch "/unscheduled_maintenances/#{unscheduled_maintenance.id}/relationships/check",
      Flapjack.dump_json(:data => {
        :type => 'check', :id => check.id
      }), jsonapi_env
    expect(last_response.status).to eq(404)
  end

  it 'cannot clear the check for a unscheduled maintenance period' do
    patch "/unscheduled_maintenances/#{unscheduled_maintenance.id}/relationships/check",
      Flapjack.dump_json(:data => {
        :type => 'check', :id => nil
      }), jsonapi_env
    expect(last_response.status).to eq(404)
  end

end
