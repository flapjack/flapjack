require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::ScheduledMaintenanceLinks', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:scheduled_maintenance) { double(Flapjack::Data::ScheduledMaintenance,
                                  :id => scheduled_maintenance_data[:id]) }
  let(:check) { double(Flapjack::Data::Check, :id => check_data[:id]) }

  let(:sm_check_by_start) { double('sm_check_by_start') }
  let(:sm_check_by_end)   { double('sm_check_by_end') }

  it 'sets a check for a scheduled maintenance period' do
    expect(Flapjack::Data::ScheduledMaintenance).to receive(:find_by_id!).with(scheduled_maintenance.id).
      and_return(scheduled_maintenance)
    expect(Flapjack::Data::Check).to receive(:find_by_id!).with(check.id).
      and_return(check)

    expect(scheduled_maintenance).to receive(:check).and_return(nil)
    expect(scheduled_maintenance).to receive(:check=).with(check)

    post "/scheduled_maintenances/#{scheduled_maintenance.id}/links/check", Flapjack.dump_json(:check => check.id), jsonapi_post_env
    expect(last_response.status).to eq(204)
  end

  it 'shows the check for a scheduled maintenance period' do
    expect(scheduled_maintenance).to receive(:check).and_return(check)

    expect(Flapjack::Data::ScheduledMaintenance).to receive(:find_by_id!).with(scheduled_maintenance.id).
      and_return(scheduled_maintenance)

    get "/scheduled_maintenances/#{scheduled_maintenance.id}/links/check"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to eq(Flapjack.dump_json(:checks => check.id))
  end

  it 'changes the check for a scheduled maintenance period' do
    expect(Flapjack::Data::ScheduledMaintenance).to receive(:find_by_id!).with(scheduled_maintenance.id).
      and_return(scheduled_maintenance)
    expect(Flapjack::Data::Check).to receive(:find_by_id!).with(check.id).
      and_return(check)

    expect(scheduled_maintenance).to receive(:check=).with(check)

    put "/scheduled_maintenances/#{scheduled_maintenance.id}/links/check", Flapjack.dump_json(:check => check.id), jsonapi_put_env
    expect(last_response.status).to eq(204)
  end

  it 'clears the check for a scheduled maintenance period' do
    expect(Flapjack::Data::ScheduledMaintenance).to receive(:find_by_id!).with(scheduled_maintenance.id).
      and_return(scheduled_maintenance)

    expect(scheduled_maintenance).to receive(:check).and_return(check)
    expect(scheduled_maintenance).to receive(:check=).with(nil)

    delete "/scheduled_maintenances/#{scheduled_maintenance.id}/links/check"
    expect(last_response.status).to eq(204)
  end

end
