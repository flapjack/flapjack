require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::ReportMethods', :sinatra => true, :logger => true do

  def app
    Flapjack::Gateways::JSONAPI
  end

  let(:entity)          { double(Flapjack::Data::Entity) }
  let(:entity_check)    { double(Flapjack::Data::EntityCheck) }

  let(:entity_id)         { '457' }
  let(:entity_name)       { 'www.example.net'}
  let(:entity_name_esc)   { URI.escape(entity_name) }
  let(:entity_check_name) { 'ping' }

  let(:entity_check_presenter) { double(Flapjack::Gateways::JSONAPI::EntityCheckPresenter) }

  let(:redis)           { double(::Redis) }

  let(:jsonapi_env) {
    {'CONTENT_TYPE' => Flapjack::Gateways::JSONAPI::JSONAPI_MEDIA_TYPE,
     'HTTP_ACCEPT'  => 'application/json; q=0.8, application/vnd.api+json'}
  }

  before(:all) do
    Flapjack::Gateways::JSONAPI.class_eval {
      set :raise_errors, true
    }
  end

  before(:each) do
    expect(Flapjack::RedisPool).to receive(:new).and_return(redis)
    Flapjack::Gateways::JSONAPI.instance_variable_set('@config', {})
    Flapjack::Gateways::JSONAPI.instance_variable_set('@logger', @logger)
    Flapjack::Gateways::JSONAPI.start
  end

  after(:each) do
    if last_response.status >= 200 && last_response.status < 300
      expect(last_response.headers.keys).to include('Access-Control-Allow-Methods')
      expect(last_response.headers['Access-Control-Allow-Origin']).to eq("*")
      unless last_response.status == 204
        expect(Oj.load(last_response.body)).to be_a(Enumerable)
        expect(last_response.headers['Content-Type']).to eq(Flapjack::Gateways::JSONAPI::JSONAPI_MEDIA_TYPE)
      end
    end
  end

  it "returns the status for all entities" do
    status = double('status')
    expect(status).to receive(:as_json).and_return({:status => 'data'})
    expect(entity_check_presenter).to receive(:status).and_return(status)

    expect(Flapjack::Gateways::JSONAPI::EntityCheckPresenter).to receive(:new).
      with(entity_check).and_return(entity_check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(entity_check)

    expect(entity).to receive(:check_list).and_return(['SSH'])

    expect(Flapjack::Data::Entity).to receive(:all).
      with(:redis => redis).and_return([entity])

    expect(entity).to receive(:name).exactly(3).times.and_return(entity_name)
    expect(entity).to receive(:id).and_return(entity_id)

    expect(entity_check).to receive(:name).twice.and_return('SSH')

    result = {
                :status_reports => [{
                  'id'    => entity_id,
                  'name'  =>  entity_name,
                  'links' => {
                    'checks' => ["#{entity_name}:SSH"],
                  }
                }],
                :linked => {
                  :checks => [{
                    :id       => "#{entity_name}:SSH",
                    :name     => 'SSH',
                    :statuses => {'status' => 'data'}
                  }]
                }
              }

    aget "/status_report/entities", {}, jsonapi_env
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "returns the status for all checks on an entity" do
    status = double('status')
    expect(status).to receive(:as_json).and_return({:status => 'data'})
    expect(entity_check_presenter).to receive(:status).and_return(status)

    expect(Flapjack::Gateways::JSONAPI::EntityCheckPresenter).to receive(:new).
      with(entity_check).and_return(entity_check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(entity_check)

    expect(entity).to receive(:check_list).and_return(['SSH'])

    expect(Flapjack::Data::Entity).to receive(:find_by_id).
      with(entity_id, :redis => redis).and_return(entity)

    expect(entity).to receive(:name).exactly(3).times.and_return(entity_name)
    expect(entity).to receive(:id).and_return(entity_id)

    expect(entity_check).to receive(:name).twice.and_return('SSH')

    result = {
                :status_reports => [{
                  'id'    => entity_id,
                  'name'  =>  entity_name,
                  'links' => {
                    'checks' => ["#{entity_name}:SSH"],
                  }
                }],
                :linked => {
                  :checks => [{
                    :id       => "#{entity_name}:SSH",
                    :name     => 'SSH',
                    :statuses => {'status' => 'data'}
                  }]
                }
              }

    aget "/status_report/entities/#{entity_id}", {}, jsonapi_env
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "should not show the status for an entity that's not found" do
    expect(Flapjack::Data::Entity).to receive(:find_by_id).
      with(entity_id, :redis => redis).and_return(nil)

    aget "/status_report/entities/#{entity_id}", {}, jsonapi_env
    expect(last_response.status).to eq(404)
  end

  it "returns the status for an entity check" do
    status = double('status')
    expect(status).to receive(:as_json).and_return({:status => 'data'})
    expect(entity_check_presenter).to receive(:status).and_return(status)

    expect(Flapjack::Gateways::JSONAPI::EntityCheckPresenter).to receive(:new).
      with(entity_check).and_return(entity_check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(entity_check)

    expect(entity).to receive(:id).and_return(entity_id)

    expect(entity).to receive(:name).and_return(entity_name)
    expect(entity_check).to receive(:entity).and_return(entity)
    expect(entity_check).to receive(:name).twice.and_return('SSH')

    result = {
                :status_reports => [{
                  'id'    => entity_id,
                  'name'  => entity_name,
                  'links' => {
                    'checks' => ["#{entity_name}:SSH"],
                  }
                }],
                :linked => {
                  :checks => [{
                    :id       => "#{entity_name}:SSH",
                    :name     => 'SSH',
                    :statuses => {'status' => 'data'}
                  }]
                }
              }

    aget "/status_report/checks/#{entity_name}:SSH", {}, jsonapi_env
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "should not show the status for a check on an entity that's not found" do
    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(nil)

    aget "/status_report/checks/#{entity_name}:SSH", {}, jsonapi_env
    expect(last_response).to be_not_found
  end

  it "should not show the status for a check that's not found on an entity" do
    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(nil)

    aget "/status_report/checks/#{entity_name}:SSH", {}, jsonapi_env
    expect(last_response).to be_not_found
  end

  it "returns a list of scheduled maintenance periods for an entity" do
    sched_maint = double('scheduled_maintenances')
    expect(sched_maint).to receive(:as_json).and_return({:scheduled_maintenances => 'data'})
    expect(entity_check_presenter).to receive(:scheduled_maintenance).and_return(sched_maint)

    expect(Flapjack::Gateways::JSONAPI::EntityCheckPresenter).to receive(:new).
      with(entity_check).and_return(entity_check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(entity_check)

    expect(entity).to receive(:check_list).and_return(['SSH'])

    expect(Flapjack::Data::Entity).to receive(:find_by_id).
      with(entity_id, :redis => redis).and_return(entity)

    expect(entity).to receive(:name).exactly(3).times.and_return(entity_name)
    expect(entity).to receive(:id).and_return(entity_id)

    expect(entity_check).to receive(:name).twice.and_return('SSH')

    result = {
                :scheduled_maintenance_reports => [{
                  'id'    => entity_id,
                  'name'  => entity_name,
                  'links' => {
                    'checks' => ["#{entity_name}:SSH"],
                  }
                }],
                :linked => {
                  :checks => [{
                    :id     => "#{entity_name}:SSH",
                    :name   => 'SSH',
                    :scheduled_maintenances => {'scheduled_maintenances' => 'data'}
                  }]
                }
              }

    aget "/scheduled_maintenance_report/entities/#{entity_id}", {}, jsonapi_env
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "returns a list of scheduled maintenance periods within a time window for an entity" do
    start  = Time.parse('1 Jan 2012')
    finish = Time.parse('6 Jan 2012')

    sched_maint = double('scheduled_maintenances')
    expect(sched_maint).to receive(:as_json).and_return({:scheduled_maintenances => 'data'})
    expect(entity_check_presenter).to receive(:scheduled_maintenance).
      with(start.to_i, finish.to_i).and_return(sched_maint)

    expect(Flapjack::Gateways::JSONAPI::EntityCheckPresenter).to receive(:new).
      with(entity_check).and_return(entity_check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(entity_check)

    expect(entity).to receive(:check_list).and_return(['SSH'])

    expect(Flapjack::Data::Entity).to receive(:find_by_id).
      with(entity_id, :redis => redis).and_return(entity)

    expect(entity).to receive(:name).exactly(3).times.and_return(entity_name)
    expect(entity).to receive(:id).and_return(entity_id)

    expect(entity_check).to receive(:name).twice.and_return('SSH')

    result = {
                :scheduled_maintenance_reports => [{
                  'id'    => entity_id,
                  'name'  =>  entity_name,
                  'links' => {
                    'checks' => ["#{entity_name}:SSH"],
                  }
                }],
                :linked => {
                  :checks => [{
                    :id     => "#{entity_name}:SSH",
                    :name   => 'SSH',
                    :scheduled_maintenances => {'scheduled_maintenances' => 'data'}
                  }]
                }
              }

    aget "/scheduled_maintenance_report/entities/#{entity_id}",
      {:start_time => start.iso8601, :end_time => finish.iso8601}, jsonapi_env
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "returns a list of scheduled maintenance periods for a check on an entity" do
    sched_maint = double('scheduled_maintenances')
    expect(sched_maint).to receive(:as_json).and_return({:scheduled_maintenances => 'data'})
    expect(entity_check_presenter).to receive(:scheduled_maintenance).and_return(sched_maint)

    expect(Flapjack::Gateways::JSONAPI::EntityCheckPresenter).to receive(:new).
      with(entity_check).and_return(entity_check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(entity_check)

    expect(entity).to receive(:id).and_return(entity_id)

    expect(entity).to receive(:name).and_return(entity_name)
    expect(entity_check).to receive(:entity).and_return(entity)
    expect(entity_check).to receive(:name).twice.and_return('SSH')

    result = {
                :scheduled_maintenance_reports => [{
                  'id'    => entity_id,
                  'name'  => entity_name,
                  'links' => {
                    'checks' => ["#{entity_name}:SSH"],
                  }
                }],
                :linked => {
                  :checks => [{
                    :id     => "#{entity_name}:SSH",
                    :name   => 'SSH',
                    :scheduled_maintenances => {'scheduled_maintenances' => 'data'}
                  }]
                }
              }

    aget "/scheduled_maintenance_report/checks/#{entity_name}:SSH", {}, jsonapi_env
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "returns a list of unscheduled maintenance periods for an entity" do
    unsched_maint = double('unscheduled_maintenances')
    expect(unsched_maint).to receive(:as_json).and_return({:unscheduled_maintenances => 'data'})
    expect(entity_check_presenter).to receive(:unscheduled_maintenance).and_return(unsched_maint)

    expect(Flapjack::Gateways::JSONAPI::EntityCheckPresenter).to receive(:new).
      with(entity_check).and_return(entity_check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(entity_check)

    expect(entity).to receive(:check_list).and_return(['SSH'])

    expect(Flapjack::Data::Entity).to receive(:find_by_id).
      with(entity_id, :redis => redis).and_return(entity)

    expect(entity).to receive(:name).exactly(3).times.and_return(entity_name)
    expect(entity).to receive(:id).and_return(entity_id)

    expect(entity_check).to receive(:name).twice.and_return('SSH')

    result = {
                :unscheduled_maintenance_reports => [{
                  'id'    => entity_id,
                  'name'  => entity_name,
                  'links' => {
                    'checks' => ["#{entity_name}:SSH"],
                  }
                }],
                :linked => {
                  :checks => [{
                    :id     => "#{entity_name}:SSH",
                    :name   => 'SSH',
                    :unscheduled_maintenances => {'unscheduled_maintenances' => 'data'}
                  }]
                }
              }

    aget "/unscheduled_maintenance_report/entities/#{entity_id}", {}, jsonapi_env
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "returns a list of unscheduled maintenance periods for a check on an entity" do
    unsched_maint = double('unscheduled_maintenances')
    expect(unsched_maint).to receive(:as_json).and_return({:unscheduled_maintenances => 'data'})
    expect(entity_check_presenter).to receive(:unscheduled_maintenance).and_return(unsched_maint)

    expect(Flapjack::Gateways::JSONAPI::EntityCheckPresenter).to receive(:new).
      with(entity_check).and_return(entity_check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(entity_check)


    expect(entity).to receive(:id).and_return(entity_id)

    expect(entity).to receive(:name).and_return(entity_name)
    expect(entity_check).to receive(:entity).and_return(entity)
    expect(entity_check).to receive(:name).twice.and_return('SSH')

    result = {
                :unscheduled_maintenance_reports => [{
                  'id'    => entity_id,
                  'name'  => entity_name,
                  'links' => {
                    'checks' => ["#{entity_name}:SSH"],
                  }
                }],
                :linked => {
                  :checks => [{
                    :id     => "#{entity_name}:SSH",
                    :name   => 'SSH',
                    :unscheduled_maintenances => {'unscheduled_maintenances' => 'data'}
                  }]
                }
              }

    aget "/unscheduled_maintenance_report/checks/#{entity_name}:SSH", {}, jsonapi_env
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "returns a list of unscheduled maintenance periods within a time window for a check an entity" do
    start  = Time.parse('1 Jan 2012')
    finish = Time.parse('6 Jan 2012')

    unsched_maint = double('scheduled_maintenances')
    expect(unsched_maint).to receive(:as_json).and_return({:unscheduled_maintenances => 'data'})
    expect(entity_check_presenter).to receive(:unscheduled_maintenance).
      with(start.to_i, finish.to_i).and_return(unsched_maint)

    expect(Flapjack::Gateways::JSONAPI::EntityCheckPresenter).to receive(:new).
      with(entity_check).and_return(entity_check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(entity_check)

    expect(entity).to receive(:id).and_return(entity_id)

    expect(entity).to receive(:name).and_return(entity_name)
    expect(entity_check).to receive(:entity).and_return(entity)
    expect(entity_check).to receive(:name).twice.and_return('SSH')

    result = {
                :unscheduled_maintenance_reports => [{
                  'id'    => entity_id,
                  'name'  => entity_name,
                  'links' => {
                    'checks' => ["#{entity_name}:SSH"],
                  }
                }],
                :linked => {
                  :checks => [{
                    :id     => "#{entity_name}:SSH",
                    :name   => 'SSH',
                    :unscheduled_maintenances => {'unscheduled_maintenances' => 'data'}
                  }]
                }
              }

    aget "/unscheduled_maintenance_report/checks/#{entity_name}:SSH",
      {:start_time => start.iso8601, :end_time => finish.iso8601}, jsonapi_env
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "returns a list of outages for a check on an entity" do
    outages = double('outages')
    expect(outages).to receive(:as_json).and_return({:outages => 'data'})
    expect(entity_check_presenter).to receive(:outage).and_return(outages)

    expect(Flapjack::Gateways::JSONAPI::EntityCheckPresenter).to receive(:new).
      with(entity_check).and_return(entity_check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(entity_check)

    expect(entity).to receive(:id).and_return(entity_id)

    expect(entity).to receive(:name).and_return(entity_name)
    expect(entity_check).to receive(:entity).and_return(entity)
    expect(entity_check).to receive(:name).twice.and_return('SSH')

    result = {
                :outage_reports => [{
                  'id'    => entity_id,
                  'name'  => entity_name,
                  'links' => {
                    'checks' => ["#{entity_name}:SSH"],
                  }
                }],
                :linked => {
                  :checks => [{
                    :id      => "#{entity_name}:SSH",
                    :name    => 'SSH',
                    :outages => {'outages' => 'data'}
                  }]
                }
              }

    aget "/outage_report/checks/#{entity_name}:SSH", {}, jsonapi_env
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "returns a list of downtimes for an entity" do
    downtime = double('downtime')
    expect(downtime).to receive(:as_json).and_return({:downtime => 'data'})
    expect(entity_check_presenter).to receive(:downtime).and_return(downtime)

    expect(Flapjack::Gateways::JSONAPI::EntityCheckPresenter).to receive(:new).
      with(entity_check).and_return(entity_check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(entity_check)

    expect(entity).to receive(:check_list).and_return(['SSH'])

    expect(Flapjack::Data::Entity).to receive(:find_by_id).
      with(entity_id, :redis => redis).and_return(entity)

    expect(entity).to receive(:name).exactly(3).times.and_return(entity_name)

    expect(entity).to receive(:id).and_return(entity_id)

    expect(entity_check).to receive(:name).twice.and_return('SSH')

    result = {
                :downtime_reports => [{
                  'id'    => entity_id,
                  'name'  => entity_name,
                  'links' => {
                    'checks' => ["#{entity_name}:SSH"],
                  }
                }],
                :linked => {
                  :checks => [{
                    :id     => "#{entity_name}:SSH",
                    :name   => 'SSH',
                    :downtimes => {'downtime' => 'data'}
                  }]
                }
              }

    aget "/downtime_report/entities/#{entity_id}", {}, jsonapi_env
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "returns a list of downtimes for a check on an entity" do
    downtime = double('downtime')
    expect(downtime).to receive(:as_json).and_return({:downtime => 'data'})
    expect(entity_check_presenter).to receive(:downtime).and_return(downtime)

    expect(Flapjack::Gateways::JSONAPI::EntityCheckPresenter).to receive(:new).
      with(entity_check).and_return(entity_check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(entity_check)

    expect(entity).to receive(:id).and_return(entity_id)

    expect(entity).to receive(:name).and_return(entity_name)
    expect(entity_check).to receive(:entity).and_return(entity)
    expect(entity_check).to receive(:name).twice.and_return('SSH')

    result = {
                :downtime_reports => [{
                  'id'    => entity_id,
                  'name'  => entity_name,
                  'links' => {
                    'checks' => ["#{entity_name}:SSH"],
                  }
                }],
                :linked => {
                  :checks => [{
                    :id     => "#{entity_name}:SSH",
                    :name   => 'SSH',
                    :downtimes => {'downtime' => 'data'}
                  }]
                }
              }

    aget "/downtime_report/checks/#{entity_name}:SSH", {}, jsonapi_env
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

end
