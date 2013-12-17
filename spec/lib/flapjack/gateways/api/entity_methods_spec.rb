require 'spec_helper'
require 'flapjack/gateways/api'

describe 'Flapjack::Gateways::API::EntityMethods', :sinatra => true, :logger => true, :json => true do

  def app
    Flapjack::Gateways::API
  end

  let(:json_data)       { {'valid' => 'json'} }
  # let(:json_response)   { '{"valid" : "json"}' }

  let(:entity)          { double(Flapjack::Data::Entity) }
  let(:all_entities)    { double('all_entities', :all => [entity]) }
  let(:no_entities)     { double('no_entities', :all => []) }

  let(:check)      { double(Flapjack::Data::Check) }
  let(:all_checks) { double('all_checks', :all => [check]) }
  let(:no_checks)  { double('no_checks', :all => []) }

  let(:entity_name)     { 'www.example.net'}
  let(:entity_name_esc) { URI.escape(entity_name) }
  let(:check_name)      { 'ping' }

  let(:entity_presenter) { double(Flapjack::Gateways::API::EntityPresenter) }
  let(:check_presenter)  { double(Flapjack::Gateways::API::CheckPresenter) }

  let(:redis)           { double(::Redis) }

  before(:all) do
    Flapjack::Gateways::API.class_eval {
      set :raise_errors, true
    }
  end

  before(:each) do
    allow(Flapjack).to receive(:redis).and_return(redis)
    Flapjack::Gateways::API.instance_variable_set('@config', {})
    Flapjack::Gateways::API.instance_variable_set('@logger', @logger)
    Flapjack::Gateways::API.start
  end

  it "returns a list of checks for an entity" do
    all_json_checks = double('all_checks', :all => [json_data])

    expect(entity).to receive(:checks).and_return(all_json_checks)
    expect(Flapjack::Data::Entity).to receive(:intersect).
      with(:name => entity_name).and_return(all_entities)

    get "/checks/#{entity_name_esc}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq([json_data].to_json)
  end

  context 'non-bulk API calls' do

    it "returns the status for all checks on an entity" do
      result = {:entity => entity_name, :check => check, :status => json_data}
      expect(entity_presenter).to receive(:status).and_return(result)

      expect(Flapjack::Gateways::API::EntityPresenter).to receive(:new).
        with(entity).and_return(entity_presenter)

     expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      get "/status/#{entity_name_esc}"
      expect(last_response).to be_ok
      expect(last_response.body).to eq([json_data].to_json)
    end

    it "should not show the status for an entity that's not found" do
      expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => entity_name).and_return(no_entities)

      get "/status/#{entity_name_esc}"
      expect(last_response).to be_forbidden
    end

    it "returns the status for a check on an entity" do
      expect(check_presenter).to receive(:status).and_return(json_data)

      expect(Flapjack::Gateways::API::CheckPresenter).to receive(:new).
        with(check).and_return(check_presenter)

      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:entity_name => entity_name, :name => check_name).and_return(all_checks)

      get "/status/#{entity_name_esc}/ping"
      expect(last_response).to be_ok
      expect(last_response.body).to eq(json_data.to_json)
    end

    it "should not show the status for a check that's not found on an entity" do
      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:entity_name => entity_name, :name => check_name).and_return(no_checks)

      get "/status/#{entity_name_esc}/ping"
      expect(last_response).to be_forbidden
    end

    it "returns a list of scheduled maintenance periods for an entity" do
      result = {:entity => entity_name, :check => check_name, :scheduled_maintenances => json_data}
      expect(entity_presenter).to receive(:scheduled_maintenances).with(nil, nil).and_return(result)
      expect(Flapjack::Gateways::API::EntityPresenter).to receive(:new).
        with(entity).and_return(entity_presenter)
      expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      get "/scheduled_maintenances/#{entity_name_esc}"
      expect(last_response).to be_ok
      expect(last_response.body).to eq([{:check => check_name, :scheduled_maintenance => json_data}].to_json)
    end

    it "returns a list of scheduled maintenance periods within a time window for an entity" do
      start  = Time.parse('1 Jan 2012')
      finish = Time.parse('6 Jan 2012')

      result = {:entity => entity_name, :check => check_name, :scheduled_maintenances => json_data}
      expect(entity_presenter).to receive(:scheduled_maintenances).with(start.to_i, finish.to_i).and_return(result)
      expect(Flapjack::Gateways::API::EntityPresenter).to receive(:new).
        with(entity).and_return(entity_presenter)
      expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      get "/scheduled_maintenances/#{entity_name_esc}?" +
        "start_time=#{CGI.escape(start.iso8601)}&end_time=#{CGI.escape(finish.iso8601)}"
      expect(last_response).to be_ok
      expect(last_response.body).to eq([{:check => check_name, :scheduled_maintenance => json_data}].to_json)
    end

    it "returns a list of scheduled maintenance periods for a check on an entity" do
      expect(check_presenter).to receive(:scheduled_maintenances).with(nil, nil).and_return(json_data)
      expect(Flapjack::Gateways::API::CheckPresenter).to receive(:new).
        with(check).and_return(check_presenter)
      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:entity_name => entity_name, :name => check_name).and_return(all_checks)

      get "/scheduled_maintenances/#{entity_name_esc}/ping"
      expect(last_response).to be_ok
      expect(last_response.body).to eq(json_data.to_json)
    end

    it "creates an acknowledgement for an entity check" do
      expect(check).to receive(:entity_name).and_return(entity_name)
      expect(check).to receive(:name).and_return(check_name)

      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:entity_name => entity_name, :name => check_name).and_return(all_checks)
      expect(Flapjack::Data::Event).to receive(:create_acknowledgement).
        with('events', entity_name, check_name, :summary => nil, :duration => (4 * 60 * 60))

      post "/acknowledgements/#{entity_name_esc}/ping"
      expect(last_response.status).to eq(204)
    end

    it "returns a list of unscheduled maintenance periods for an entity" do
      result = {:entity => entity_name, :check => check_name, :unscheduled_maintenances => json_data}
      expect(entity_presenter).to receive(:unscheduled_maintenances).with(nil, nil).and_return(result)
      expect(Flapjack::Gateways::API::EntityPresenter).to receive(:new).
        with(entity).and_return(entity_presenter)
      expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      get "/unscheduled_maintenances/#{entity_name_esc}"
      expect(last_response).to be_ok
      expect(last_response.body).to eq([{:check => check_name, :unscheduled_maintenance => json_data}].to_json)
    end

    it "returns a list of unscheduled maintenance periods for a check on an entity" do
      expect(check_presenter).to receive(:unscheduled_maintenances).with(nil, nil).and_return(json_data)
      expect(Flapjack::Gateways::API::CheckPresenter).to receive(:new).
        with(check).and_return(check_presenter)
      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:entity_name => entity_name, :name => check_name).and_return(all_checks)

      get "/unscheduled_maintenances/#{entity_name_esc}/ping"
      expect(last_response).to be_ok
      expect(last_response.body).to eq(json_data.to_json)
    end

    it "returns a list of unscheduled maintenance periods within a time window for a check an entity" do
      start    = Time.parse('1 Jan 2012')
      finish   = Time.parse('6 Jan 2012')

      expect(check_presenter).to receive(:unscheduled_maintenances).with(start.to_i, finish.to_i).and_return(json_data)
      expect(Flapjack::Gateways::API::CheckPresenter).to receive(:new).
        with(check).and_return(check_presenter)
      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:entity_name => entity_name, :name => check_name).and_return(all_checks)

      get "/unscheduled_maintenances/#{entity_name_esc}/ping" +
        "?start_time=#{CGI.escape(start.iso8601)}&end_time=#{CGI.escape(finish.iso8601)}"
      expect(last_response).to be_ok
      expect(last_response.body).to eq(json_data.to_json)
    end

    it "returns a list of outages for an entity" do
      result = {:entity => entity_name, :check => check_name, :outages => json_data}
      expect(entity_presenter).to receive(:outages).with(nil, nil).and_return(result)
      expect(Flapjack::Gateways::API::EntityPresenter).to receive(:new).
        with(entity).and_return(entity_presenter)
      expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      get "/outages/#{entity_name_esc}"
      expect(last_response).to be_ok
      expect(last_response.body).to eq([{:check => check_name, :outages => json_data}].to_json)
    end

    it "returns a list of outages for a check on an entity" do
      expect(check_presenter).to receive(:outages).with(nil, nil).and_return(json_data)
      expect(Flapjack::Gateways::API::CheckPresenter).to receive(:new).
        with(check).and_return(check_presenter)
      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:entity_name => entity_name, :name => check_name).and_return(all_checks)

      get "/outages/#{entity_name_esc}/ping"
      expect(last_response).to be_ok
      expect(last_response.body).to eq(json_data.to_json)
    end

    it "returns a list of downtimes for an entity" do
      result = {:entity => entity_name, :check => check_name, :downtime => json_data}
      expect(entity_presenter).to receive(:downtime).with(nil, nil).and_return(result)
      expect(Flapjack::Gateways::API::EntityPresenter).to receive(:new).
        with(entity).and_return(entity_presenter)
      expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      get "/downtime/#{entity_name_esc}"
      expect(last_response).to be_ok
      expect(last_response.body).to eq([{:check => check_name, :downtime => json_data}].to_json)
    end

    it "returns a list of downtimes for a check on an entity" do
      expect(check_presenter).to receive(:downtime).with(nil, nil).and_return(json_data)
      expect(Flapjack::Gateways::API::CheckPresenter).to receive(:new).
        with(check).and_return(check_presenter)
      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:entity_name => entity_name, :name => check_name).and_return(all_checks)

      get "/downtime/#{entity_name_esc}/ping"
      expect(last_response).to be_ok
      expect(last_response.body).to eq(json_data.to_json)
    end

    it "creates a test notification event for check on an entity" do
      expect(entity).to receive(:name).and_return(entity_name)
      expect(check).to receive(:entity).and_return(entity)
      expect(check).to receive(:entity_name).and_return(entity_name)
      expect(check).to receive(:name).and_return('foo')
      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:entity_name => entity_name, :name => 'foo').and_return(all_checks)

      expect(Flapjack::Data::Event).to receive(:test_notifications).
        with('events', entity_name, 'foo', an_instance_of(Hash))

      post "/test_notifications/#{entity_name_esc}/foo"
      expect(last_response.status).to eq(204)
    end

  end

  context 'bulk API calls' do

    it "returns the status for all checks on an entity" do
      result = [{:entity => entity_name, :check => check_name, :status => json_data}]
      expect(entity_presenter).to receive(:status).and_return(result)

      expect(Flapjack::Gateways::API::EntityPresenter).to receive(:new).
        with(entity).and_return(entity_presenter)

      expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      get "/status", :entity => entity_name
      expect(last_response.body).to eq(result.to_json)
    end

    it "should not show the status for an entity that's not found" do
      expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => entity_name).and_return(no_entities)

      get "/status", :entity => entity_name
      expect(last_response).to be_forbidden
    end

    it "returns the status for a check on an entity" do
      result = [{:entity => entity_name, :check => check_name, :status => json_data}]
      expect(check_presenter).to receive(:status).and_return(json_data)

      expect(Flapjack::Gateways::API::CheckPresenter).to receive(:new).
        with(check).and_return(check_presenter)

      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:entity_name => entity_name, :name => check_name).and_return(all_checks)

      get "/status", :check => {entity_name => check_name}
      expect(last_response).to be_ok
      expect(last_response.body).to eq(result.to_json)
    end

    it "should not show the status for a check that's not found on an entity" do
      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:entity_name => entity_name, :name => check_name).and_return(no_checks)

      get "/status", :check => {entity_name => check_name}
      expect(last_response).to be_forbidden
    end

    it "creates an acknowledgement for an entity check" do
      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:entity_name => entity_name, :name => check_name).and_return(all_checks)

      expect(check).to receive(:entity_name).and_return(entity_name)
      expect(check).to receive(:name).and_return(check_name)

      expect(Flapjack::Data::Event).to receive(:create_acknowledgement).
        with('events', entity_name, check_name, :summary => nil, :duration => (4 * 60 * 60))

      post '/acknowledgements',:check => {entity_name => check_name}
      expect(last_response.status).to eq(204)
    end

    it "deletes an unscheduled maintenance period for an entity check" do
      end_time = Time.now + (60 * 60) # an hour from now
      expect(check).to receive(:clear_unscheduled_maintenance).with(end_time.to_i)

      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:entity_name => entity_name, :name => check_name).and_return(all_checks)

      delete "/unscheduled_maintenances", :check => {entity_name => check_name}, :end_time => end_time.iso8601
      expect(last_response.status).to eq(204)
    end

    it "creates a scheduled maintenance period for an entity check" do
      start = Time.at(Time.now.to_i + (60 * 60)) # an hour from now
      duration = (2 * 60 * 60)     # two hours
      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:entity_name => entity_name, :name => check_name).and_return(all_checks)

      sched_maint = double(Flapjack::Data::ScheduledMaintenance)
      expect(Flapjack::Data::ScheduledMaintenance).to receive(:new).
        with(:start_time => start.to_i, :end_time => start.to_i + duration,
             :summary => 'test').and_return(sched_maint)
      expect(sched_maint).to receive(:save).and_return(true)

      expect(check).to receive(:add_scheduled_maintenance).
        with(sched_maint)

      post "/scheduled_maintenances/#{entity_name_esc}/ping?" +
         "start_time=#{CGI.escape(start.iso8601)}&summary=test&duration=#{duration}"
      expect(last_response.status).to eq(204)
    end

    it "doesn't create a scheduled maintenance period if the start time isn't passed" do
      duration = (2 * 60 * 60)     # two hours

      post "/scheduled_maintenances/#{entity_name_esc}/ping?" +
         "summary=test&duration=#{duration}"
      expect(last_response.status).to eq(403)
    end

    it "deletes a scheduled maintenance period for an entity check" do
      start = Time.at(Time.now.to_i + (60 * 60)) # an hour from now

      sched_maint = double(Flapjack::Data::ScheduledMaintenance)
      all_sched_maints = double('all_sched_maints', :all => [sched_maint])

      sched_maints = double('sched_maints')
      expect(sched_maints).to receive(:intersect_range).
        with(start.to_i, start.to_i, :by_score => true).
        and_return(all_sched_maints)
      expect(check).to receive(:scheduled_maintenances_by_start).and_return(sched_maints)
      expect(check).to receive(:end_scheduled_maintenance).with(sched_maint, an_instance_of(Time))

      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:entity_name => entity_name, :name => check_name).and_return(all_checks)

      delete "/scheduled_maintenances", :check => {entity_name => check_name}, :start_time => start.iso8601
      expect(last_response.status).to eq(204)
    end

    it "doesn't delete a scheduled maintenance period if the start time isn't passed" do
      expect(check).not_to receive(:end_scheduled_maintenance)

      delete "/scheduled_maintenances", :check => {entity_name => check_name}
      expect(last_response.status).to eq(403)
    end

    it "deletes scheduled maintenance periods for multiple entity checks" do
      start = Time.at(Time.now.to_i + (60 * 60)) # an hour from now

      sched_maint = double(Flapjack::Data::ScheduledMaintenance)
      all_sched_maints = double('all_sched_maints', :all => [sched_maint])

      sched_maint_2 = double(Flapjack::Data::ScheduledMaintenance)
      all_sched_maints_2 = double('all_sched_maints', :all => [sched_maint_2])

      check_2 = double(Flapjack::Data::Check)

      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:entity_name => entity_name, :name => check_name).and_return(all_checks)

      all_checks_2 = double('all_checks_2', :all => [check_2])
      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:entity_name => entity_name, :name => 'foo').and_return(all_checks_2)

      sched_maints = double('sched_maints')
      expect(sched_maints).to receive(:intersect_range).
        with(start.to_i, start.to_i, :by_score => true).
        and_return(all_sched_maints)
      sched_maints_2 = double('sched_maints_2')
      expect(sched_maints_2).to receive(:intersect_range).
        with(start.to_i, start.to_i, :by_score => true).
        and_return(all_sched_maints_2)

      expect(check).to receive(:scheduled_maintenances_by_start).and_return(sched_maints)
      expect(check_2).to receive(:scheduled_maintenances_by_start).and_return(sched_maints_2)

      expect(check).to receive(:end_scheduled_maintenance).with(sched_maint, an_instance_of(Time))
      expect(check_2).to receive(:end_scheduled_maintenance).with(sched_maint_2, an_instance_of(Time))

      delete "/scheduled_maintenances", :check => {entity_name => [check_name, 'foo']}, :start_time => start.iso8601
      expect(last_response.status).to eq(204)
    end

    it "returns a list of scheduled maintenance periods for an entity" do
      result = [{:entity => entity_name, :check => check_name, :scheduled_maintenances => json_data}]

      expect(entity_presenter).to receive(:scheduled_maintenances).with(nil, nil).and_return(result)

      expect(Flapjack::Gateways::API::EntityPresenter).to receive(:new).
        with(entity).and_return(entity_presenter)

      expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      get "/scheduled_maintenances", :entity => entity_name
      expect(last_response).to be_ok
      expect(last_response.body).to eq(result.to_json)
    end

    it "returns a list of scheduled maintenance periods within a time window for an entity" do
      start  = Time.parse('1 Jan 2012')
      finish = Time.parse('6 Jan 2012')

      result = [{:entity => entity_name, :check => check_name, :scheduled_maintenances => json_data}]

      expect(entity_presenter).to receive(:scheduled_maintenances).with(start.to_i, finish.to_i).and_return(result)

      expect(Flapjack::Gateways::API::EntityPresenter).to receive(:new).
        with(entity).and_return(entity_presenter)

      expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      get "/scheduled_maintenances", :entity => entity_name,
        :start_time => start.iso8601, :end_time => finish.iso8601
      expect(last_response).to be_ok
      expect(last_response.body).to eq(result.to_json)
    end

    it "returns a list of scheduled maintenance periods for a check on an entity" do
      result = [{:entity => entity_name, :check => check_name, :scheduled_maintenances => json_data}]

      expect(check_presenter).to receive(:scheduled_maintenances).with(nil, nil).and_return(json_data)

      expect(Flapjack::Gateways::API::CheckPresenter).to receive(:new).
        with(check).and_return(check_presenter)

      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:entity_name => entity_name, :name => check_name).and_return(all_checks)

      get "/scheduled_maintenances", :check => {entity_name => check_name}
      expect(last_response).to be_ok
      expect(last_response.body).to eq(result.to_json)
    end

    it "returns a list of unscheduled maintenance periods for an entity" do
      result = [{:entity => entity_name, :check => check_name, :unscheduled_maintenances => json_data}]

      expect(entity_presenter).to receive(:unscheduled_maintenances).with(nil, nil).and_return(result)

      expect(Flapjack::Gateways::API::EntityPresenter).to receive(:new).
        with(entity).and_return(entity_presenter)

      expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      get "/unscheduled_maintenances", :entity => entity_name
      expect(last_response).to be_ok
      expect(last_response.body).to eq(result.to_json)
    end

    it "returns a list of unscheduled maintenance periods for a check on an entity" do
      result = [{:entity => entity_name, :check => check_name, :unscheduled_maintenances => json_data}]

      expect(check_presenter).to receive(:unscheduled_maintenances).with(nil, nil).and_return(json_data)

      expect(Flapjack::Gateways::API::CheckPresenter).to receive(:new).
        with(check).and_return(check_presenter)

      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:entity_name => entity_name, :name => check_name).and_return(all_checks)

      get "/unscheduled_maintenances", :check => {entity_name => check_name}
      expect(last_response).to be_ok
      expect(last_response.body).to eq(result.to_json)
    end

    it "returns a list of unscheduled maintenance periods within a time window for a check an entity" do
      start  = Time.parse('1 Jan 2012')
      finish = Time.parse('6 Jan 2012')

      result = [{:entity => entity_name, :check => check_name, :unscheduled_maintenances => json_data}]

      expect(check_presenter).to receive(:unscheduled_maintenances).with(start.to_i, finish.to_i).and_return(json_data)

      expect(Flapjack::Gateways::API::CheckPresenter).to receive(:new).
        with(check).and_return(check_presenter)

      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:entity_name => entity_name, :name => check_name).and_return(all_checks)

      get "/unscheduled_maintenances", :check => {entity_name => check_name},
        :start_time => start.iso8601, :end_time => finish.iso8601
      expect(last_response).to be_ok
      expect(last_response.body).to eq(result.to_json)
    end

    it "returns a list of outages, for one whole entity and two checks on another entity" do
      json_data_2 = {'other' => 'data'}
      json_data_3 = {'more' => 'data'}

      entity_2_name = 'entity_2'
      entity_2 = double(Flapjack::Data::Entity)

      result = [{:entity => entity_name,   :check => check_name, :outages => json_data},
                {:entity => entity_2_name, :check => 'foo', :outages => json_data_2},
                {:entity => entity_2_name, :check => 'bar', :outages => json_data_3}]

      foo_check = double(Flapjack::Data::Check)
      all_foo_checks = double('all_foo_checks', :all => [foo_check])
      bar_check = double(Flapjack::Data::Check)
      all_bar_checks = double('all_bar_checks', :all => [bar_check])

      foo_check_presenter = double(Flapjack::Gateways::API::CheckPresenter)
      bar_check_presenter = double(Flapjack::Gateways::API::CheckPresenter)

      expect(entity_presenter).to receive(:outages).with(nil, nil).and_return(result[0])
      expect(foo_check_presenter).to receive(:outages).with(nil, nil).and_return(json_data_2)
      expect(bar_check_presenter).to receive(:outages).with(nil, nil).and_return(json_data_3)

      expect(Flapjack::Gateways::API::EntityPresenter).to receive(:new).
        with(entity).and_return(entity_presenter)

      expect(Flapjack::Gateways::API::CheckPresenter).to receive(:new).
        with(foo_check).and_return(foo_check_presenter)
      expect(Flapjack::Gateways::API::CheckPresenter).to receive(:new).
        with(bar_check).and_return(bar_check_presenter)

      expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:entity_name => entity_2_name, :name => 'foo').and_return(all_foo_checks)
      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:entity_name => entity_2_name, :name => 'bar').and_return(all_bar_checks)

      get "/outages", :entity => entity_name, :check => {entity_2_name => ['foo', 'bar']}
      expect(last_response).to be_ok
      expect(last_response.body).to eq(result.to_json)
    end

    it "returns a list of outages for a check on an entity" do
      result = [{:entity => entity_name, :check => check_name, :outages => json_data}]

      expect(check_presenter).to receive(:outages).with(nil, nil).and_return(json_data)

      expect(Flapjack::Gateways::API::CheckPresenter).to receive(:new).
        with(check).and_return(check_presenter)

      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:entity_name => entity_name, :name => check_name).and_return(all_checks)

      get "/outages", :check => {entity_name => check_name}
      expect(last_response).to be_ok
      expect(last_response.body).to eq(result.to_json)
    end

    it "returns a list of downtimes for an entity" do
      result = [{:entity => entity_name, :check => check_name, :downtime => json_data}]

      expect(entity_presenter).to receive(:downtime).with(nil, nil).and_return(result)

      expect(Flapjack::Gateways::API::EntityPresenter).to receive(:new).
        with(entity).and_return(entity_presenter)

      expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      get "/downtime", :entity => entity_name
      expect(last_response).to be_ok
      expect(last_response.body).to eq(result.to_json)
    end

    it "returns a list of downtimes for a check on an entity" do
      result = [{:entity => entity_name, :check => check_name, :downtime => json_data}]

      expect(check_presenter).to receive(:downtime).with(nil, nil).and_return(json_data)

      expect(Flapjack::Gateways::API::CheckPresenter).to receive(:new).
        with(check).and_return(check_presenter)

      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:entity_name => entity_name, :name => check_name).and_return(all_checks)

      get "/downtime", :check => {entity_name => check_name}
      expect(last_response).to be_ok
      expect(last_response.body).to eq(result.to_json)
    end

    it "creates test notification events for all checks on an entity" do
      expect(check).to receive(:entity).and_return(entity)
      expect(check).to receive(:entity_name).and_return(entity_name)
      expect(check).to receive(:name).twice.and_return(check_name)

      check_2 = double(Flapjack::Data::Check)
      expect(check_2).to receive(:entity).and_return(entity)
      expect(check_2).to receive(:entity_name).and_return(entity_name)
      expect(check_2).to receive(:name).twice.and_return('foo')

      all_checks = double('all_checks', :all => [check, check_2])

      expect(entity).to receive(:checks).and_return(all_checks)
      expect(entity).to receive(:name).twice.and_return(entity_name)
      expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      expect(Flapjack::Data::Event).to receive(:test_notifications).
        with('events', entity_name, check_name, an_instance_of(Hash))

      expect(Flapjack::Data::Event).to receive(:test_notifications).
        with('events', entity_name, 'foo', an_instance_of(Hash))

      post '/test_notifications', :entity => entity_name
      expect(last_response.status).to eq(204)
    end

    it "creates a test notification event for check on an entity" do
      expect(entity).to receive(:name).and_return(entity_name)
      expect(check).to receive(:entity).and_return(entity)
      expect(check).to receive(:entity_name).and_return(entity_name)
      expect(check).to receive(:name).and_return(check)
      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:entity_name => entity_name, :name => check_name).and_return(all_checks)

      expect(Flapjack::Data::Event).to receive(:test_notifications).
      with('events', entity_name, check, an_instance_of(Hash))

      post '/test_notifications', :check => {entity_name => check_name}
      expect(last_response.status).to eq(204)
    end

    it "creates entities from a submitted list" do
      entities = {'entities' =>
        [
         {"id" => "10001",
          "name" => "clientx-app-01",
          "contacts" => ["0362","0363","0364"]
         },
         {"id" => "10002",
          "name" => "clientx-app-02",
          "contacts" => ["0362"]
         }
        ]
      }

      expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => 'clientx-app-01').and_return(no_entities)
      expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => 'clientx-app-02').and_return(no_entities)

      expect(Flapjack::Data::Contact).to receive(:find_by_id).exactly(4).times.and_return(nil)

      expect(entity).to receive(:valid?).and_return(true)
      expect(entity).to receive(:save).and_return(true)
      expect(entity).to receive(:id).and_return('10001')

      entity_2 = double(Flapjack::Data::Entity)
      expect(entity_2).to receive(:valid?).and_return(true)
      expect(entity_2).to receive(:save).and_return(true)
      expect(entity_2).to receive(:id).and_return('10002')

      expect(Flapjack::Data::Entity).to receive(:new).
        with(:id => '10001', :name => 'clientx-app-01', :enabled => false).
        and_return(entity)
      expect(Flapjack::Data::Entity).to receive(:new).
        with(:id => '10002', :name => 'clientx-app-02', :enabled => false).
        and_return(entity_2)

      post "/entities", entities.to_json, {'CONTENT_TYPE' => 'application/json'}
      expect(last_response.status).to eq(204)
    end

    it "does not create entities if the data is improperly formatted" do
      expect(Flapjack::Data::Entity).not_to receive(:new)

      post "/entities", {'entities' => ["Hello", "there"]}.to_json,
        {'CONTENT_TYPE' => 'application/json'}
      expect(last_response.status).to eq(403)
    end

  end

  context "tags" do

    it "sets a single tag on an entity and returns current tags" do
      tags = ['web']
      expect(entity).to receive(:tags=).with(Set.new(tags))
      expect(entity).to receive(:tags).twice.and_return(Set.new, Set.new(tags))
      expect(entity).to receive(:save).and_return(true)
      expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      post "entities/#{entity_name}/tags", :tag => tags.first
      expect(last_response).to be_ok
      expect(last_response.body).to eq( tags.to_json )
    end

    it "does not set a single tag on an entity that's not found" do
      expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => entity_name).and_return(no_entities)

      post "entities/#{entity_name}/tags", :tag => 'web'
      expect(last_response).to be_forbidden
    end

    it "sets multiple tags on an entity and returns current tags" do
      tags = ['web', 'app']
      expect(entity).to receive(:tags=).with(Set.new(tags))
      expect(entity).to receive(:tags).twice.and_return(Set.new, Set.new(tags))
      expect(entity).to receive(:save).and_return(true)
      expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      # NB submitted at a lower level as tag[]=web&tag[]=app
      post "entities/#{entity_name}/tags", :tag => tags
      expect(last_response).to be_ok
      expect(last_response.body).to eq( tags.to_json )
    end

    it "does not set multiple tags on an entity that's not found" do
      expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => entity_name).and_return(no_entities)

      post "entities/#{entity_name}/tags", :tag => ['web', 'app']
      expect(last_response).to be_forbidden
    end

    it "removes a single tag from an entity" do
      tags = ['web']
      expect(entity).to receive(:tags=).with(Set.new)
      expect(entity).to receive(:tags).and_return(Set.new(tags))
      expect(entity).to receive(:save).and_return(true)
      expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      delete "entities/#{entity_name}/tags", :tag => tags.first
      expect(last_response.status).to eq(204)
    end

    it "does not remove a single tag from an entity that's not found" do
      expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => entity_name).and_return(no_entities)

      delete "entities/#{entity_name}/tags", :tag => 'web'
      expect(last_response).to be_forbidden
    end

    it "removes multiple tags from an entity" do
      tags = ['web', 'app']
      expect(entity).to receive(:tags=).with(Set.new)
      expect(entity).to receive(:tags).and_return(Set.new(tags))
      expect(entity).to receive(:save).and_return(true)
      expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      delete "entities/#{entity_name}/tags", :tag => tags
      expect(last_response.status).to eq(204)
    end

    it "does not remove multiple tags from an entity that's not found" do
      expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => entity_name).and_return(no_entities)

      delete "entities/#{entity_name}/tags", :tag => ['web', 'app']
      expect(last_response).to be_forbidden
    end

    it "gets all tags on an entity" do
      expect(entity).to receive(:tags).and_return(Set.new(['web', 'app']))

      expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      get "entities/#{entity_name}/tags"
      expect(last_response).to be_ok
      expect(last_response.body).to eq( ['web', 'app'].to_json )
    end

    it "does not get all tags on an entity that's not found" do
      expect(Flapjack::Data::Entity).to receive(:intersect).
        with(:name => entity_name).and_return(no_entities)

      get "entities/#{entity_name}/tags"
      expect(last_response).to be_forbidden
    end

  end

end
