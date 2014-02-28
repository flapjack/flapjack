require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::ReportMethods', :sinatra => true, :logger => true do

  def app
    Flapjack::Gateways::JSONAPI
  end

  let(:entity)          { double(Flapjack::Data::Entity) }
  let(:entity_check)    { double(Flapjack::Data::EntityCheck) }

  let(:entity_name)       { 'www.example.net'}
  let(:entity_name_esc)   { URI.escape(entity_name) }
  let(:entity_check_name) { 'ping' }

  let(:entity_check_presenter) { double(Flapjack::Gateways::JSONAPI::EntityCheckPresenter) }

  let(:redis)           { double(::Redis) }

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

  it "returns the status for all checks on an entity" do
    status = double('status')
    expect(status).to receive(:as_json).and_return({:status => 'data'})
    expect(entity_check_presenter).to receive(:status).and_return(status)

    expect(Flapjack::Gateways::JSONAPI::EntityCheckPresenter).to receive(:new).
      with(entity_check).and_return(entity_check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(entity_check)

    expect(entity).to receive(:check_list).and_return(['SSH'])

    expect(Flapjack::Data::Entity).to receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    expect(entity).to receive(:id).and_return('232')

    expect(entity_check).to receive(:name).twice.and_return('SSH')

    result = {
                :entities => [{
                  'id'    => '232',
                  'name'  =>  entity_name,
                  'links' => {
                    'checks' => ["#{entity_name}:SSH"],
                  }
                }],
                :linked => {
                  :checks => [{
                    :id     => "#{entity_name}:SSH",
                    :name   => 'SSH',
                    :status => {'status' => 'data'}
                  }]
                }
              }

    aget "/reports/status", :entity => entity_name
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "should not show the status for an entity that's not found" do
    expect(Flapjack::Data::Entity).to receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(nil)

    aget "/reports/status", :entity => entity_name
    expect(last_response.status).to eq(404)
  end

  it "returns the status for a check on an entity" do
    status = double('status')
    expect(status).to receive(:as_json).and_return({:status => 'data'})
    expect(entity_check_presenter).to receive(:status).and_return(status)

    expect(Flapjack::Gateways::JSONAPI::EntityCheckPresenter).to receive(:new).
      with(entity_check).and_return(entity_check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(entity_check)

    expect(Flapjack::Data::Entity).to receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    expect(entity).to receive(:id).and_return('232')

    expect(entity_check).to receive(:name).twice.and_return('SSH')

    result = {
                :entities => [{
                  'id'    => '232',
                  'name'  =>  entity_name,
                  'links' => {
                    'checks' => ["#{entity_name}:SSH"],
                  }
                }],
                :linked => {
                  :checks => [{
                    :id     => "#{entity_name}:SSH",
                    :name   => 'SSH',
                    :status => {'status' => 'data'}
                  }]
                }
              }

    aget "/reports/status", :check => "#{entity_name}:SSH"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "should not show the status for a check on an entity that's not found" do
    expect(Flapjack::Data::Entity).to receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(nil)

    aget "/reports/status", :check => "#{entity_name}:SSH"
    expect(last_response).to be_not_found
  end

  it "should not show the status for a check that's not found on an entity" do
    expect(Flapjack::Data::Entity).to receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)
    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(nil)

    aget "/reports/status", :check => "#{entity_name}:SSH"
    expect(last_response).to be_not_found
  end

  it "returns a list of scheduled maintenance periods for an entity" do
    sched_maint = double('scheduled_maintenances')
    expect(sched_maint).to receive(:as_json).and_return({:scheduled_maintenances => 'data'})
    expect(entity_check_presenter).to receive(:scheduled_maintenances).and_return(sched_maint)

    expect(Flapjack::Gateways::JSONAPI::EntityCheckPresenter).to receive(:new).
      with(entity_check).and_return(entity_check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(entity_check)

    expect(entity).to receive(:check_list).and_return(['SSH'])

    expect(Flapjack::Data::Entity).to receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    expect(entity).to receive(:id).and_return('232')

    expect(entity_check).to receive(:name).twice.and_return('SSH')

    result = {
                :entities => [{
                  'id'    => '232',
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

    aget "/reports/scheduled_maintenances", :entity => entity_name
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "returns a list of scheduled maintenance periods within a time window for an entity" do
    start  = Time.parse('1 Jan 2012')
    finish = Time.parse('6 Jan 2012')

    sched_maint = double('scheduled_maintenances')
    expect(sched_maint).to receive(:as_json).and_return({:scheduled_maintenances => 'data'})
    expect(entity_check_presenter).to receive(:scheduled_maintenances).
      with(start.to_i, finish.to_i).and_return(sched_maint)

    expect(Flapjack::Gateways::JSONAPI::EntityCheckPresenter).to receive(:new).
      with(entity_check).and_return(entity_check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(entity_check)

    expect(Flapjack::Data::Entity).to receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    expect(entity).to receive(:id).and_return('232')

    expect(entity_check).to receive(:name).twice.and_return('SSH')

    result = {
                :entities => [{
                  'id'    => '232',
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

    aget "/reports/scheduled_maintenances", :check => "#{entity_name}:SSH",
      :start_time => start.iso8601, :end_time => finish.iso8601
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "returns a list of scheduled maintenance periods for a check on an entity" do
    sched_maint = double('scheduled_maintenances')
    expect(sched_maint).to receive(:as_json).and_return({:scheduled_maintenances => 'data'})
    expect(entity_check_presenter).to receive(:scheduled_maintenances).and_return(sched_maint)

    expect(Flapjack::Gateways::JSONAPI::EntityCheckPresenter).to receive(:new).
      with(entity_check).and_return(entity_check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(entity_check)

    expect(Flapjack::Data::Entity).to receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    expect(entity).to receive(:id).and_return('232')

    expect(entity_check).to receive(:name).twice.and_return('SSH')

    result = {
                :entities => [{
                  'id'    => '232',
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

    aget "/reports/scheduled_maintenances", :check => "#{entity_name}:SSH"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "returns a list of unscheduled maintenance periods for an entity" do
    unsched_maint = double('unscheduled_maintenances')
    expect(unsched_maint).to receive(:as_json).and_return({:unscheduled_maintenances => 'data'})
    expect(entity_check_presenter).to receive(:unscheduled_maintenances).and_return(unsched_maint)

    expect(Flapjack::Gateways::JSONAPI::EntityCheckPresenter).to receive(:new).
      with(entity_check).and_return(entity_check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(entity_check)

    expect(entity).to receive(:check_list).and_return(['SSH'])

    expect(Flapjack::Data::Entity).to receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    expect(entity).to receive(:id).and_return('232')

    expect(entity_check).to receive(:name).twice.and_return('SSH')

    result = {
                :entities => [{
                  'id'    => '232',
                  'name'  =>  entity_name,
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

    aget "/reports/unscheduled_maintenances", :entity => entity_name
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "returns a list of unscheduled maintenance periods for a check on an entity" do
    unsched_maint = double('unscheduled_maintenances')
    expect(unsched_maint).to receive(:as_json).and_return({:unscheduled_maintenances => 'data'})
    expect(entity_check_presenter).to receive(:unscheduled_maintenances).and_return(unsched_maint)

    expect(Flapjack::Gateways::JSONAPI::EntityCheckPresenter).to receive(:new).
      with(entity_check).and_return(entity_check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(entity_check)

    expect(Flapjack::Data::Entity).to receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    expect(entity).to receive(:id).and_return('232')

    expect(entity_check).to receive(:name).twice.and_return('SSH')

    result = {
                :entities => [{
                  'id'    => '232',
                  'name'  =>  entity_name,
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

    aget "/reports/unscheduled_maintenances", :check => "#{entity_name}:SSH"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "returns a list of unscheduled maintenance periods within a time window for a check an entity" do
    start  = Time.parse('1 Jan 2012')
    finish = Time.parse('6 Jan 2012')

    unsched_maint = double('scheduled_maintenances')
    expect(unsched_maint).to receive(:as_json).and_return({:unscheduled_maintenances => 'data'})
    expect(entity_check_presenter).to receive(:unscheduled_maintenances).
      with(start.to_i, finish.to_i).and_return(unsched_maint)

    expect(Flapjack::Gateways::JSONAPI::EntityCheckPresenter).to receive(:new).
      with(entity_check).and_return(entity_check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(entity_check)

    expect(Flapjack::Data::Entity).to receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    expect(entity).to receive(:id).and_return('232')

    expect(entity_check).to receive(:name).twice.and_return('SSH')

    result = {
                :entities => [{
                  'id'    => '232',
                  'name'  =>  entity_name,
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

    aget "/reports/unscheduled_maintenances", :check => "#{entity_name}:SSH",
      :start_time => start.iso8601, :end_time => finish.iso8601
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "returns a list of outages, for one whole entity and two checks on another entity" do
    entity_check_2_presenter = double(Flapjack::Gateways::JSONAPI::EntityCheckPresenter)
    entity_check_3_presenter = double(Flapjack::Gateways::JSONAPI::EntityCheckPresenter)

    outages_1 = double('outages_1')
    expect(outages_1).to receive(:as_json).and_return('data_1')
    expect(entity_check_presenter).to receive(:outages).and_return(outages_1)

    outages_2 = double('outages_2')
    expect(outages_2).to receive(:as_json).and_return('data_2')
    expect(entity_check_2_presenter).to receive(:outages).and_return(outages_2)

    outages_3 = double('outages_3')
    expect(outages_3).to receive(:as_json).and_return('data_3')
    expect(entity_check_3_presenter).to receive(:outages).and_return(outages_3)

    expect(entity).to receive(:check_list).and_return(['SSH'])

    entity_2 = double(Flapjack::Data::Entity)
    entity_2_name = "abcde.com"

    entity_check_2 = double(Flapjack::Data::EntityCheck)
    entity_check_3 = double(Flapjack::Data::EntityCheck)

    expect(Flapjack::Gateways::JSONAPI::EntityCheckPresenter).to receive(:new).
      with(entity_check).and_return(entity_check_presenter)
    expect(Flapjack::Gateways::JSONAPI::EntityCheckPresenter).to receive(:new).
      with(entity_check_2).and_return(entity_check_2_presenter)
    expect(Flapjack::Gateways::JSONAPI::EntityCheckPresenter).to receive(:new).
      with(entity_check_3).and_return(entity_check_3_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(entity_check)
    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_2_name, 'ping', :redis => redis).and_return(entity_check_2)
    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_2_name, 'http', :redis => redis).and_return(entity_check_3)

    expect(Flapjack::Data::Entity).to receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)
    expect(Flapjack::Data::Entity).to receive(:find_by_name).
      with(entity_2_name, :redis => redis).and_return(entity_2)

    expect(entity).to receive(:id).and_return('232')
    expect(entity_2).to receive(:id).and_return('233')

    expect(entity_check).to receive(:name).twice.and_return('SSH')
    expect(entity_check_2).to receive(:name).twice.and_return('ping')
    expect(entity_check_3).to receive(:name).twice.and_return('http')

    result = {
                :entities => [{
                  'id'    => '232',
                  'name'  =>  entity_name,
                  'links' => {
                    'checks' => ["#{entity_name}:SSH"],
                  }
                },
                {
                  'id'    => '233',
                  'name'  =>  entity_2_name,
                  'links' => {
                    'checks' => ["#{entity_2_name}:ping", "#{entity_2_name}:http"],
                  }
                }],
                :linked => {
                  :checks => [{
                    :id      => "#{entity_name}:SSH",
                    :name    => 'SSH',
                    :outages => 'data_1'
                  },
                  {
                    :id      => "#{entity_2_name}:ping",
                    :name    => 'ping',
                    :outages => 'data_2'
                  },
                  {
                    :id      => "#{entity_2_name}:http",
                    :name    => 'http',
                    :outages => 'data_3'
                  },
                ]
                }
              }

    aget "/reports/outages", :entity => entity_name,
      :check => ["#{entity_2_name}:ping", "#{entity_2_name}:http"]
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "returns a list of outages for a check on an entity" do
    outages = double('outages')
    expect(outages).to receive(:as_json).and_return({:outages => 'data'})
    expect(entity_check_presenter).to receive(:outages).and_return(outages)

    expect(Flapjack::Gateways::JSONAPI::EntityCheckPresenter).to receive(:new).
      with(entity_check).and_return(entity_check_presenter)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity_name).
      with(entity_name, 'SSH', :redis => redis).and_return(entity_check)

    expect(Flapjack::Data::Entity).to receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    expect(entity).to receive(:id).and_return('232')

    expect(entity_check).to receive(:name).twice.and_return('SSH')

    result = {
                :entities => [{
                  'id'    => '232',
                  'name'  =>  entity_name,
                  'links' => {
                    'checks' => ["#{entity_name}:SSH"],
                  }
                }],
                :linked => {
                  :checks => [{
                    :id     => "#{entity_name}:SSH",
                    :name   => 'SSH',
                    :outages => {'outages' => 'data'}
                  }]
                }
              }

    aget "/reports/outages", :check => "#{entity_name}:SSH"
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

    expect(Flapjack::Data::Entity).to receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    expect(entity).to receive(:id).and_return('232')

    expect(entity_check).to receive(:name).twice.and_return('SSH')

    result = {
                :entities => [{
                  'id'    => '232',
                  'name'  =>  entity_name,
                  'links' => {
                    'checks' => ["#{entity_name}:SSH"],
                  }
                }],
                :linked => {
                  :checks => [{
                    :id     => "#{entity_name}:SSH",
                    :name   => 'SSH',
                    :downtime => {'downtime' => 'data'}
                  }]
                }
              }

    aget "/reports/downtime", :entity => entity_name
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

    expect(Flapjack::Data::Entity).to receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    expect(entity).to receive(:id).and_return('232')

    expect(entity_check).to receive(:name).twice.and_return('SSH')

    result = {
                :entities => [{
                  'id'    => '232',
                  'name'  =>  entity_name,
                  'links' => {
                    'checks' => ["#{entity_name}:SSH"],
                  }
                }],
                :linked => {
                  :checks => [{
                    :id     => "#{entity_name}:SSH",
                    :name   => 'SSH',
                    :downtime => {'downtime' => 'data'}
                  }]
                }
              }

    aget "/reports/downtime", :check => "#{entity_name}:SSH"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

end
