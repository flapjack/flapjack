require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::ReportMethods', :sinatra => true, :logger => true do

  include_context "jsonapi"

  let(:entity)          { double(Flapjack::Data::Entity) }
  let(:entity_check)    { double(Flapjack::Data::EntityCheck) }

  let(:entity_id)         { '457' }
  let(:entity_name)       { 'www.example.net'}
  let(:entity_name_esc)   { URI.escape(entity_name) }
  let(:entity_check_name) { 'ping' }

  let(:check_presenter) { double(Flapjack::Gateways::JSONAPI::CheckPresenter) }

  it "returns the status for all entities" do
    status = {'status' => 'data'}
    expect(check_presenter).to receive(:status).and_return(status)

    expect(Flapjack::Gateways::JSONAPI::CheckPresenter).to receive(:new).
      with(entity_check).and_return(check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
      with(entity, 'SSH', :redis => redis).and_return(entity_check)

    expect(entity).to receive(:check_list).and_return(['SSH'])

    expect(Flapjack::Data::Entity).to receive(:all).
      with(:redis => redis).and_return([entity])

    expect(entity).to receive(:name).twice.and_return(entity_name)
    expect(entity).to receive(:id).twice.and_return(entity_id)

    expect(entity_check).to receive(:check).exactly(3).times.and_return('SSH')

    result = {
              :status_reports => [{
                :status => 'data',
                :links => {
                  :entity => [entity_id],
                  :check  => ["#{entity_name}:SSH"]
                }}],
              :linked => {
                :entities => [{
                  :id    => entity_id,
                  :name  =>  entity_name,
                  :links => {
                    :checks => ["#{entity_name}:SSH"],
                  }
                }],
                :checks => [{
                  :id       => "#{entity_name}:SSH",
                  :name     => 'SSH',
                }]
              }
             }

    aget "/status_report/entities"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "returns the status for all checks on an entity" do
    status = {'status' => 'data'}
    expect(check_presenter).to receive(:status).and_return(status)

    expect(Flapjack::Gateways::JSONAPI::CheckPresenter).to receive(:new).
      with(entity_check).and_return(check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
      with(entity, 'SSH', :redis => redis).and_return(entity_check)

    expect(entity).to receive(:check_list).and_return(['SSH'])

    expect(Flapjack::Data::Entity).to receive(:find_by_id).
      with(entity_id, :redis => redis).and_return(entity)

    expect(entity).to receive(:name).twice.and_return(entity_name)
    expect(entity).to receive(:id).twice.and_return(entity_id)

    expect(entity_check).to receive(:check).exactly(3).times.and_return('SSH')

    result = {
              :status_reports => [{
                :status => 'data',
                :links => {
                  :entity => [entity_id],
                  :check  => ["#{entity_name}:SSH"]
                }}],
              :linked => {
                :entities => [{
                  :id    => entity_id,
                  :name  =>  entity_name,
                  :links => {
                    :checks => ["#{entity_name}:SSH"],
                  }
                }],
                :checks => [{
                  :id       => "#{entity_name}:SSH",
                  :name     => 'SSH',
                }]
                }
              }

    aget "/status_report/entities/#{entity_id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "should not show the status for an entity that's not found" do
    expect(Flapjack::Data::Entity).to receive(:find_by_id).
      with(entity_id, :redis => redis).and_return(nil)

    aget "/status_report/entities/#{entity_id}"
    expect(last_response.status).to eq(404)
  end

  it "returns the status for an entity check" do
    status = {'status' => 'data'}
    expect(check_presenter).to receive(:status).and_return(status)

    expect(Flapjack::Gateways::JSONAPI::CheckPresenter).to receive(:new).
      with(entity_check).and_return(check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(entity_check)

    expect(entity).to receive(:name).twice.and_return(entity_name)
    expect(entity).to receive(:id).and_return(entity_id)

    expect(entity_check).to receive(:entity).and_return(entity)
    expect(entity_check).to receive(:check).exactly(3).times.and_return('SSH')

    result = {
              :status_reports => [{
                :status => 'data',
                :links => {
                  :entity => [entity_id],
                  :check  => ["#{entity_name}:SSH"]
                }}],
              :linked => {
                :entities => [{
                  :id    => entity_id,
                  :name  =>  entity_name,
                  :links => {
                    :checks => ["#{entity_name}:SSH"],
                  }
                }],
                :checks => [{
                  :id       => "#{entity_name}:SSH",
                  :name     => 'SSH',
                }]
                }
              }

    aget "/status_report/checks/#{entity_name}:SSH"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "should not show the status for a check on an entity that's not found" do
    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(nil)

    aget "/status_report/checks/#{entity_name}:SSH"
    expect(last_response).to be_not_found
  end

  it "should not show the status for a check that's not found on an entity" do
    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(nil)

    aget "/status_report/checks/#{entity_name}:SSH"
    expect(last_response).to be_not_found
  end

  it "returns a list of scheduled maintenance periods for an entity" do
    sched_maint = {:scheduled_maintenances => 'data'}
    expect(check_presenter).to receive(:scheduled_maintenance).and_return(sched_maint)

    expect(Flapjack::Gateways::JSONAPI::CheckPresenter).to receive(:new).
      with(entity_check).and_return(check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
      with(entity, 'SSH', :redis => redis).and_return(entity_check)

    expect(entity).to receive(:check_list).and_return(['SSH'])

    expect(Flapjack::Data::Entity).to receive(:find_by_id).
      with(entity_id, :redis => redis).and_return(entity)

    expect(entity).to receive(:name).twice.and_return(entity_name)
    expect(entity).to receive(:id).twice.and_return(entity_id)

    expect(entity_check).to receive(:check).exactly(3).times.and_return('SSH')

    result = {
              :scheduled_maintenance_reports => [{
                :scheduled_maintenances => 'data',
                :links => {
                  :entity => [entity_id],
                  :check  => ["#{entity_name}:SSH"]
                }}],
              :linked => {
                :entities => [{
                  :id    => entity_id,
                  :name  =>  entity_name,
                  :links => {
                    :checks => ["#{entity_name}:SSH"],
                  }
                }],
                :checks => [{
                  :id       => "#{entity_name}:SSH",
                  :name     => 'SSH',
                }]
                }
              }

    aget "/scheduled_maintenance_report/entities/#{entity_id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "returns a list of scheduled maintenance periods within a time window for an entity" do
    start  = Time.parse('1 Jan 2012')
    finish = Time.parse('6 Jan 2012')

    sched_maint = {:scheduled_maintenances => 'data'}
    expect(check_presenter).to receive(:scheduled_maintenance).
      with(start.to_i, finish.to_i).and_return(sched_maint)

    expect(Flapjack::Gateways::JSONAPI::CheckPresenter).to receive(:new).
      with(entity_check).and_return(check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
      with(entity, 'SSH', :redis => redis).and_return(entity_check)

    expect(entity).to receive(:check_list).and_return(['SSH'])

    expect(Flapjack::Data::Entity).to receive(:find_by_id).
      with(entity_id, :redis => redis).and_return(entity)

    expect(entity).to receive(:name).twice.and_return(entity_name)
    expect(entity).to receive(:id).twice.and_return(entity_id)

    expect(entity_check).to receive(:check).exactly(3).times.and_return('SSH')

    result = {
              :scheduled_maintenance_reports => [{
                :scheduled_maintenances => 'data',
                :links => {
                  :entity => [entity_id],
                  :check  => ["#{entity_name}:SSH"]
                }}],
              :linked => {
                :entities => [{
                  :id    => entity_id,
                  :name  =>  entity_name,
                  :links => {
                    :checks => ["#{entity_name}:SSH"],
                  }
                }],
                :checks => [{
                  :id       => "#{entity_name}:SSH",
                  :name     => 'SSH',
                }]
                }
              }

    aget "/scheduled_maintenance_report/entities/#{entity_id}",
      :start_time => start.iso8601, :end_time => finish.iso8601
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "returns a list of scheduled maintenance periods for a check on an entity" do
    sched_maint = {:scheduled_maintenances => 'data'}
    expect(check_presenter).to receive(:scheduled_maintenance).and_return(sched_maint)

    expect(Flapjack::Gateways::JSONAPI::CheckPresenter).to receive(:new).
      with(entity_check).and_return(check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(entity_check)

    expect(entity).to receive(:name).twice.and_return(entity_name)
    expect(entity).to receive(:id).and_return(entity_id)

    expect(entity_check).to receive(:entity).and_return(entity)
    expect(entity_check).to receive(:check).exactly(3).times.and_return('SSH')

    result = {
              :scheduled_maintenance_reports => [{
                :scheduled_maintenances => 'data',
                :links => {
                  :entity => [entity_id],
                  :check  => ["#{entity_name}:SSH"]
                }}],
              :linked => {
                :entities => [{
                  :id    => entity_id,
                  :name  =>  entity_name,
                  :links => {
                    :checks => ["#{entity_name}:SSH"],
                  }
                }],
                :checks => [{
                  :id       => "#{entity_name}:SSH",
                  :name     => 'SSH',
                }]
                }
              }

    aget "/scheduled_maintenance_report/checks/#{entity_name}:SSH"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "returns a list of unscheduled maintenance periods for an entity" do
    unsched_maint = {:unscheduled_maintenances => 'data'}
    expect(check_presenter).to receive(:unscheduled_maintenance).and_return(unsched_maint)

    expect(Flapjack::Gateways::JSONAPI::CheckPresenter).to receive(:new).
      with(entity_check).and_return(check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
      with(entity, 'SSH', :redis => redis).and_return(entity_check)

    expect(entity).to receive(:check_list).and_return(['SSH'])

    expect(Flapjack::Data::Entity).to receive(:find_by_id).
      with(entity_id, :redis => redis).and_return(entity)

    expect(entity).to receive(:name).twice.and_return(entity_name)
    expect(entity).to receive(:id).twice.and_return(entity_id)

    expect(entity_check).to receive(:check).exactly(3).times.and_return('SSH')

    result = {
              :unscheduled_maintenance_reports => [{
                :unscheduled_maintenances => 'data',
                :links => {
                  :entity => [entity_id],
                  :check  => ["#{entity_name}:SSH"]
                }}],
              :linked => {
                :entities => [{
                  :id    => entity_id,
                  :name  =>  entity_name,
                  :links => {
                    :checks => ["#{entity_name}:SSH"],
                  }
                }],
                :checks => [{
                  :id       => "#{entity_name}:SSH",
                  :name     => 'SSH',
                }]
                }
              }

    aget "/unscheduled_maintenance_report/entities/#{entity_id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "returns a list of unscheduled maintenance periods for a check on an entity" do
    unsched_maint = {:unscheduled_maintenances => 'data'}
    expect(check_presenter).to receive(:unscheduled_maintenance).and_return(unsched_maint)

    expect(Flapjack::Gateways::JSONAPI::CheckPresenter).to receive(:new).
      with(entity_check).and_return(check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(entity_check)

    expect(entity).to receive(:name).twice.and_return(entity_name)
    expect(entity).to receive(:id).and_return(entity_id)

    expect(entity_check).to receive(:entity).and_return(entity)
    expect(entity_check).to receive(:check).exactly(3).times.and_return('SSH')

    result = {
              :unscheduled_maintenance_reports => [{
                :unscheduled_maintenances => 'data',
                :links => {
                  :entity => [entity_id],
                  :check  => ["#{entity_name}:SSH"]
                }}],
              :linked => {
                :entities => [{
                  :id    => entity_id,
                  :name  =>  entity_name,
                  :links => {
                    :checks => ["#{entity_name}:SSH"],
                  }
                }],
                :checks => [{
                  :id       => "#{entity_name}:SSH",
                  :name     => 'SSH',
                }]
                }
              }

    aget "/unscheduled_maintenance_report/checks/#{entity_name}:SSH"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "returns a list of unscheduled maintenance periods within a time window for a check an entity" do
    start  = Time.parse('1 Jan 2012')
    finish = Time.parse('6 Jan 2012')

    unsched_maint = {:unscheduled_maintenances => 'data'}
    expect(check_presenter).to receive(:unscheduled_maintenance).
      with(start.to_i, finish.to_i).and_return(unsched_maint)

    expect(Flapjack::Gateways::JSONAPI::CheckPresenter).to receive(:new).
      with(entity_check).and_return(check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(entity_check)

    expect(entity).to receive(:name).twice.and_return(entity_name)
    expect(entity).to receive(:id).and_return(entity_id)

    expect(entity_check).to receive(:entity).and_return(entity)
    expect(entity_check).to receive(:check).exactly(3).times.and_return('SSH')

    result = {
              :unscheduled_maintenance_reports => [{
                :unscheduled_maintenances => 'data',
                :links => {
                  :entity => [entity_id],
                  :check  => ["#{entity_name}:SSH"]
                }}],
              :linked => {
                :entities => [{
                  :id    => entity_id,
                  :name  =>  entity_name,
                  :links => {
                    :checks => ["#{entity_name}:SSH"],
                  }
                }],
                :checks => [{
                  :id       => "#{entity_name}:SSH",
                  :name     => 'SSH',
                }]
                }
              }

    aget "/unscheduled_maintenance_report/checks/#{entity_name}:SSH",
      :start_time => start.iso8601, :end_time => finish.iso8601
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "returns a list of outages for a check on an entity" do
    outages = {:outages => 'data'}
    expect(check_presenter).to receive(:outage).and_return(outages)

    expect(Flapjack::Gateways::JSONAPI::CheckPresenter).to receive(:new).
      with(entity_check).and_return(check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(entity_check)

    expect(entity).to receive(:name).twice.and_return(entity_name)
    expect(entity).to receive(:id).and_return(entity_id)

    expect(entity_check).to receive(:entity).and_return(entity)
    expect(entity_check).to receive(:check).exactly(3).times.and_return('SSH')

    result = {
              :outage_reports => [{
                :outages => 'data',
                :links => {
                  :entity => [entity_id],
                  :check  => ["#{entity_name}:SSH"]
                }}],
              :linked => {
                :entities => [{
                  :id    => entity_id,
                  :name  =>  entity_name,
                  :links => {
                    :checks => ["#{entity_name}:SSH"],
                  }
                }],
                :checks => [{
                  :id       => "#{entity_name}:SSH",
                  :name     => 'SSH',
                }]
                }
              }

    aget "/outage_report/checks/#{entity_name}:SSH"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "returns a list of downtimes for an entity" do
    downtime = {:downtime => 'data'}
    expect(check_presenter).to receive(:downtime).and_return(downtime)

    expect(Flapjack::Gateways::JSONAPI::CheckPresenter).to receive(:new).
      with(entity_check).and_return(check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
      with(entity, 'SSH', :redis => redis).and_return(entity_check)

    expect(entity).to receive(:check_list).and_return(['SSH'])

    expect(Flapjack::Data::Entity).to receive(:find_by_id).
      with(entity_id, :redis => redis).and_return(entity)

    expect(entity).to receive(:name).twice.and_return(entity_name)
    expect(entity).to receive(:id).twice.and_return(entity_id)

    expect(entity_check).to receive(:check).exactly(3).times.and_return('SSH')

    result = {
              :downtime_reports => [{
                :downtime => 'data',
                :links => {
                  :entity => [entity_id],
                  :check  => ["#{entity_name}:SSH"]
                }}],
              :linked => {
                :entities => [{
                  :id    => entity_id,
                  :name  =>  entity_name,
                  :links => {
                    :checks => ["#{entity_name}:SSH"],
                  }
                }],
                :checks => [{
                  :id       => "#{entity_name}:SSH",
                  :name     => 'SSH',
                }]
                }
              }

    aget "/downtime_report/entities/#{entity_id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "returns a list of downtimes for a check on an entity" do
    downtime = {:downtime => 'data'}
    expect(check_presenter).to receive(:downtime).and_return(downtime)

    expect(Flapjack::Gateways::JSONAPI::CheckPresenter).to receive(:new).
      with(entity_check).and_return(check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(entity_check)

    expect(entity).to receive(:name).twice.and_return(entity_name)
    expect(entity).to receive(:id).and_return(entity_id)

    expect(entity_check).to receive(:entity).and_return(entity)
    expect(entity_check).to receive(:check).exactly(3).times.and_return('SSH')

    result = {
              :downtime_reports => [{
                :downtime => 'data',
                :links => {
                  :entity => [entity_id],
                  :check  => ["#{entity_name}:SSH"]
                }}],
              :linked => {
                :entities => [{
                  :id    => entity_id,
                  :name  =>  entity_name,
                  :links => {
                    :checks => ["#{entity_name}:SSH"],
                  }
                }],
                :checks => [{
                  :id       => "#{entity_name}:SSH",
                  :name     => 'SSH',
                }]
                }
              }

    aget "/downtime_report/checks/#{entity_name}:SSH"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

end
