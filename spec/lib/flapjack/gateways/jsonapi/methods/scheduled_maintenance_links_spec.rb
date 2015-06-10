require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::ScheduledMaintenanceLinks', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:scheduled_maintenance) { double(Flapjack::Data::ScheduledMaintenance,
                                  :id => scheduled_maintenance_data[:id]) }
  let(:check) { double(Flapjack::Data::Check, :id => check_data[:id]) }

  it 'shows the check for a scheduled maintenance period' do
    expect(Flapjack::Data::ScheduledMaintenance).to receive(:lock).with(Flapjack::Data::Check).and_yield

    expect(scheduled_maintenance).to receive(:check).and_return(check)

    scheduled_maintenances = double('scheduled_maintenances', :all => [scheduled_maintenance])
    expect(scheduled_maintenances).to receive(:empty?).and_return(false)
    expect(Flapjack::Data::ScheduledMaintenance).to receive(:intersect).
      with(:id => scheduled_maintenance.id).and_return(scheduled_maintenances)

    get "/scheduled_maintenances/#{scheduled_maintenance.id}/check"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => {:type => 'check', :id => check.id},
      :links => {
        :self    => "http://example.org/scheduled_maintenances/#{scheduled_maintenance.id}/relationships/check",
        :related => "http://example.org/scheduled_maintenances/#{scheduled_maintenance.id}/check",
      }
    ))
  end

  it 'cannot change the check for a scheduled maintenance period' do
    patch "/scheduled_maintenances/#{scheduled_maintenance.id}/relationships/check",
    Flapjack.dump_json(:data => {
      :type => 'check', :id => check.id
    }), jsonapi_env
    expect(last_response.status).to eq(404)
  end

  it 'cannot clear the check for a scheduled maintenance period' do
    patch "/scheduled_maintenances/#{scheduled_maintenance.id}/relationships/check",
    Flapjack.dump_json(:data => {
      :type => 'check', :id => nil
    }), jsonapi_env
    expect(last_response.status).to eq(404)
  end

end
