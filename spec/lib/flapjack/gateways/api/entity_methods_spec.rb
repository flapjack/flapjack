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

  let(:entity_check)      { double(Flapjack::Data::Check) }
  let(:all_entity_checks) { double('all_entity_checks', :all => [entity_check]) }
  let(:no_entity_checks)  { double('no_entity_checks', :all => []) }

  let(:entity_name)     { 'www.example.net'}
  let(:entity_name_esc) { URI.escape(entity_name) }
  let(:check)           { 'ping' }

  let(:entity_presenter)       { double(Flapjack::Gateways::API::EntityPresenter) }
  let(:entity_check_presenter) { double(Flapjack::Gateways::API::EntityCheckPresenter) }

  let(:redis)           { double(::Redis) }

  before(:all) do
    Flapjack::Gateways::API.class_eval {
      set :raise_errors, true
    }
  end

  before(:each) do
    Flapjack.stub(:redis).and_return(redis)
    Flapjack::Gateways::API.instance_variable_set('@config', {})
    Flapjack::Gateways::API.instance_variable_set('@logger', @logger)
    Flapjack::Gateways::API.start
  end

  it "returns a list of checks for an entity" do
    entity.should_receive(:check_list).and_return([check])
    Flapjack::Data::Entity.should_receive(:intersect).
      with(:name => entity_name).and_return(all_entities)

    get "/checks/#{entity_name_esc}"
    last_response.should be_ok
    last_response.body.should == [check].to_json
  end

  context 'non-bulk API calls' do

    it "returns the status for all checks on an entity" do
      result = {:entity => entity_name, :check => check, :status => json_data}
      entity_presenter.should_receive(:status).and_return(result)

      Flapjack::Gateways::API::EntityPresenter.should_receive(:new).
        with(entity).and_return(entity_presenter)

     Flapjack::Data::Entity.should_receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      get "/status/#{entity_name_esc}"
      last_response.should be_ok
      last_response.body.should == [json_data].to_json
    end

    it "should not show the status for an entity that's not found" do
      Flapjack::Data::Entity.should_receive(:intersect).
        with(:name => entity_name).and_return(no_entities)

      get "/status/#{entity_name_esc}"
      last_response.should be_forbidden
    end

    it "returns the status for a check on an entity" do
      entity_check_presenter.should_receive(:status).and_return(json_data)

      Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
        with(entity_check).and_return(entity_check_presenter)

      Flapjack::Data::Check.should_receive(:intersect).
        with(:entity_name => entity_name, :name => check).and_return(all_entity_checks)

      get "/status/#{entity_name_esc}/#{check}"
      last_response.should be_ok
      last_response.body.should == json_data.to_json
    end

    it "should not show the status for a check that's not found on an entity" do
      Flapjack::Data::Check.should_receive(:intersect).
        with(:entity_name => entity_name, :name => check).and_return(no_entity_checks)

      get "/status/#{entity_name_esc}/#{check}"
      last_response.should be_forbidden
    end

    it "returns a list of scheduled maintenance periods for an entity" do
      result = {:entity => entity_name, :check => check, :scheduled_maintenances => json_data}
      entity_presenter.should_receive(:scheduled_maintenances).with(nil, nil).and_return(result)
      Flapjack::Gateways::API::EntityPresenter.should_receive(:new).
        with(entity).and_return(entity_presenter)
      Flapjack::Data::Entity.should_receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      get "/scheduled_maintenances/#{entity_name_esc}"
      last_response.should be_ok
      last_response.body.should == [{:check => check, :scheduled_maintenance => json_data}].to_json
    end

    it "returns a list of scheduled maintenance periods within a time window for an entity" do
      start  = Time.parse('1 Jan 2012')
      finish = Time.parse('6 Jan 2012')

      result = {:entity => entity_name, :check => check, :scheduled_maintenances => json_data}
      entity_presenter.should_receive(:scheduled_maintenances).with(start.to_i, finish.to_i).and_return(result)
      Flapjack::Gateways::API::EntityPresenter.should_receive(:new).
        with(entity).and_return(entity_presenter)
      Flapjack::Data::Entity.should_receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      get "/scheduled_maintenances/#{entity_name_esc}?" +
        "start_time=#{CGI.escape(start.iso8601)}&end_time=#{CGI.escape(finish.iso8601)}"
      last_response.should be_ok
      last_response.body.should == [{:check => check, :scheduled_maintenance => json_data}].to_json
    end

    it "returns a list of scheduled maintenance periods for a check on an entity" do
      entity_check_presenter.should_receive(:scheduled_maintenances).with(nil, nil).and_return(json_data)
      Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
        with(entity_check).and_return(entity_check_presenter)
      Flapjack::Data::Check.should_receive(:intersect).
        with(:entity_name => entity_name, :name => check).and_return(all_entity_checks)

      get "/scheduled_maintenances/#{entity_name_esc}/#{check}"
      last_response.should be_ok
      last_response.body.should == json_data.to_json
    end

    it "creates an acknowledgement for an entity check" do
      entity_check.should_receive(:entity_name).and_return(entity_name)
      entity_check.should_receive(:check).and_return(check)

      Flapjack::Data::Check.should_receive(:intersect).
        with(:entity_name => entity_name, :name => check).and_return(all_entity_checks)
      Flapjack::Data::Event.should_receive(:create_acknowledgement).
        with('events', entity_name, check, :summary => nil, :duration => (4 * 60 * 60))

      post "/acknowledgements/#{entity_name_esc}/#{check}"
      last_response.status.should == 204
    end

    it "returns a list of unscheduled maintenance periods for an entity" do
      result = {:entity => entity_name, :check => check, :unscheduled_maintenances => json_data}
      entity_presenter.should_receive(:unscheduled_maintenances).with(nil, nil).and_return(result)
      Flapjack::Gateways::API::EntityPresenter.should_receive(:new).
        with(entity).and_return(entity_presenter)
      Flapjack::Data::Entity.should_receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      get "/unscheduled_maintenances/#{entity_name_esc}"
      last_response.should be_ok
      last_response.body.should == [{:check => check, :unscheduled_maintenance => json_data}].to_json
    end

    it "returns a list of unscheduled maintenance periods for a check on an entity" do
      entity_check_presenter.should_receive(:unscheduled_maintenances).with(nil, nil).and_return(json_data)
      Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
        with(entity_check).and_return(entity_check_presenter)
      Flapjack::Data::Check.should_receive(:intersect).
        with(:entity_name => entity_name, :name => check).and_return(all_entity_checks)

      get "/unscheduled_maintenances/#{entity_name_esc}/#{check}"
      last_response.should be_ok
      last_response.body.should == json_data.to_json
    end

    it "returns a list of unscheduled maintenance periods within a time window for a check an entity" do
      start    = Time.parse('1 Jan 2012')
      finish   = Time.parse('6 Jan 2012')

      entity_check_presenter.should_receive(:unscheduled_maintenances).with(start.to_i, finish.to_i).and_return(json_data)
      Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
        with(entity_check).and_return(entity_check_presenter)
      Flapjack::Data::Check.should_receive(:intersect).
        with(:entity_name => entity_name, :name => check).and_return(all_entity_checks)

      get "/unscheduled_maintenances/#{entity_name_esc}/#{check}" +
        "?start_time=#{CGI.escape(start.iso8601)}&end_time=#{CGI.escape(finish.iso8601)}"
      last_response.should be_ok
      last_response.body.should == json_data.to_json
    end

    it "returns a list of outages for an entity" do
      result = {:entity => entity_name, :check => check, :outages => json_data}
      entity_presenter.should_receive(:outages).with(nil, nil).and_return(result)
      Flapjack::Gateways::API::EntityPresenter.should_receive(:new).
        with(entity).and_return(entity_presenter)
      Flapjack::Data::Entity.should_receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      get "/outages/#{entity_name_esc}"
      last_response.should be_ok
      last_response.body.should == [{:check => check, :outages => json_data}].to_json
    end

    it "returns a list of outages for a check on an entity" do
      entity_check_presenter.should_receive(:outages).with(nil, nil).and_return(json_data)
      Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
        with(entity_check).and_return(entity_check_presenter)
      Flapjack::Data::Check.should_receive(:intersect).
        with(:entity_name => entity_name, :name => check).and_return(all_entity_checks)

      get "/outages/#{entity_name_esc}/#{check}"
      last_response.should be_ok
      last_response.body.should == json_data.to_json
    end

    it "returns a list of downtimes for an entity" do
      result = {:entity => entity_name, :check => check, :downtime => json_data}
      entity_presenter.should_receive(:downtime).with(nil, nil).and_return(result)
      Flapjack::Gateways::API::EntityPresenter.should_receive(:new).
        with(entity).and_return(entity_presenter)
      Flapjack::Data::Entity.should_receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      get "/downtime/#{entity_name_esc}"
      last_response.should be_ok
      last_response.body.should == [{:check => check, :downtime => json_data}].to_json
    end

    it "returns a list of downtimes for a check on an entity" do
      entity_check_presenter.should_receive(:downtime).with(nil, nil).and_return(json_data)
      Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
        with(entity_check).and_return(entity_check_presenter)
      Flapjack::Data::Check.should_receive(:intersect).
        with(:entity_name => entity_name, :name => check).and_return(all_entity_checks)

      get "/downtime/#{entity_name_esc}/#{check}"
      last_response.should be_ok
      last_response.body.should == json_data.to_json
    end

    it "creates a test notification event for check on an entity" do
      entity.should_receive(:name).and_return(entity_name)
      entity_check.should_receive(:entity).and_return(entity)
      entity_check.should_receive(:entity_name).and_return(entity_name)
      entity_check.should_receive(:check).and_return('foo')
      Flapjack::Data::Check.should_receive(:intersect).
        with(:entity_name => entity_name, :name => 'foo').and_return(all_entity_checks)

      Flapjack::Data::Event.should_receive(:test_notifications).
        with('events', entity_name, 'foo', an_instance_of(Hash))

      post "/test_notifications/#{entity_name_esc}/foo"
      last_response.status.should == 204
    end

  end

  context 'bulk API calls' do

    it "returns the status for all checks on an entity" do
      result = [{:entity => entity_name, :check => check, :status => json_data}]
      entity_presenter.should_receive(:status).and_return(result)

      Flapjack::Gateways::API::EntityPresenter.should_receive(:new).
        with(entity).and_return(entity_presenter)

      Flapjack::Data::Entity.should_receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      get "/status", :entity => entity_name
      last_response.body.should == result.to_json
    end

    it "should not show the status for an entity that's not found" do
      Flapjack::Data::Entity.should_receive(:intersect).
        with(:name => entity_name).and_return(no_entities)

      get "/status", :entity => entity_name
      last_response.should be_forbidden
    end

    it "returns the status for a check on an entity" do
      result = [{:entity => entity_name, :check => check, :status => json_data}]
      entity_check_presenter.should_receive(:status).and_return(json_data)

      Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
        with(entity_check).and_return(entity_check_presenter)

      Flapjack::Data::Check.should_receive(:intersect).
        with(:entity_name => entity_name, :name => check).and_return(all_entity_checks)

      get "/status", :check => {entity_name => check}
      last_response.should be_ok
      last_response.body.should == result.to_json
    end

    it "should not show the status for a check that's not found on an entity" do
      Flapjack::Data::Check.should_receive(:intersect).
        with(:entity_name => entity_name, :name => check).and_return(no_entity_checks)

      get "/status", :check => {entity_name => check}
      last_response.should be_forbidden
    end

    it "creates an acknowledgement for an entity check" do
      Flapjack::Data::Check.should_receive(:intersect).
        with(:entity_name => entity_name, :name => check).and_return(all_entity_checks)

      entity_check.should_receive(:entity_name).and_return(entity_name)
      entity_check.should_receive(:check).and_return(check)

      Flapjack::Data::Event.should_receive(:create_acknowledgement).
        with('events', entity_name, check, :summary => nil, :duration => (4 * 60 * 60))

      post '/acknowledgements',:check => {entity_name => check}
      last_response.status.should == 204
    end

    it "deletes an unscheduled maintenance period for an entity check" do
      end_time = Time.now + (60 * 60) # an hour from now
      entity_check.should_receive(:clear_unscheduled_maintenance).with(end_time.to_i)

      Flapjack::Data::Check.should_receive(:intersect).
        with(:entity_name => entity_name, :name => check).and_return(all_entity_checks)

      delete "/unscheduled_maintenances", :check => {entity_name => check}, :end_time => end_time.iso8601
      last_response.status.should == 204
    end

    it "creates a scheduled maintenance period for an entity check" do
      start = Time.at(Time.now.to_i + (60 * 60)) # an hour from now
      duration = (2 * 60 * 60)     # two hours
      Flapjack::Data::Check.should_receive(:intersect).
        with(:entity_name => entity_name, :name => check).and_return(all_entity_checks)

      sched_maint = double(Flapjack::Data::ScheduledMaintenance)
      Flapjack::Data::ScheduledMaintenance.should_receive(:new).
        with(:start_time => start.to_i, :end_time => start.to_i + duration,
             :summary => 'test').and_return(sched_maint)
      sched_maint.should_receive(:save).and_return(true)

      entity_check.should_receive(:add_scheduled_maintenance).
        with(sched_maint)

      post "/scheduled_maintenances/#{entity_name_esc}/#{check}?" +
         "start_time=#{CGI.escape(start.iso8601)}&summary=test&duration=#{duration}"
      last_response.status.should == 204
    end

    it "doesn't create a scheduled maintenance period if the start time isn't passed" do
      duration = (2 * 60 * 60)     # two hours

      post "/scheduled_maintenances/#{entity_name_esc}/#{check}?" +
         "summary=test&duration=#{duration}"
      last_response.status.should == 403
    end

    it "deletes a scheduled maintenance period for an entity check" do
      start = Time.at(Time.now.to_i + (60 * 60)) # an hour from now

      sched_maint = double(Flapjack::Data::ScheduledMaintenance)
      all_sched_maints = double('all_sched_maints', :all => [sched_maint])

      sched_maints = double('sched_maints')
      sched_maints.should_receive(:intersect_range).
        with(start.to_i, start.to_i, :by_score => true).
        and_return(all_sched_maints)
      entity_check.should_receive(:scheduled_maintenances_by_start).and_return(sched_maints)
      entity_check.should_receive(:end_scheduled_maintenance).with(sched_maint, an_instance_of(Fixnum))

      Flapjack::Data::Check.should_receive(:intersect).
        with(:entity_name => entity_name, :name => check).and_return(all_entity_checks)

      delete "/scheduled_maintenances", :check => {entity_name => check}, :start_time => start.iso8601
      last_response.status.should == 204
    end

    it "doesn't delete a scheduled maintenance period if the start time isn't passed" do
      entity_check.should_not_receive(:end_scheduled_maintenance)

      delete "/scheduled_maintenances", :check => {entity_name => check}
      last_response.status.should == 403
    end

    it "deletes scheduled maintenance periods for multiple entity checks" do
      start = Time.at(Time.now.to_i + (60 * 60)) # an hour from now

      sched_maint = double(Flapjack::Data::ScheduledMaintenance)
      all_sched_maints = double('all_sched_maints', :all => [sched_maint])

      sched_maint_2 = double(Flapjack::Data::ScheduledMaintenance)
      all_sched_maints_2 = double('all_sched_maints', :all => [sched_maint_2])

      entity_check_2 = double(Flapjack::Data::Check)

      Flapjack::Data::Check.should_receive(:intersect).
        with(:entity_name => entity_name, :name => check).and_return(all_entity_checks)

      all_entity_checks_2 = double('all_entity_checks_2', :all => [entity_check_2])
      Flapjack::Data::Check.should_receive(:intersect).
        with(:entity_name => entity_name, :name => 'foo').and_return(all_entity_checks_2)

      sched_maints = double('sched_maints')
      sched_maints.should_receive(:intersect_range).
        with(start.to_i, start.to_i, :by_score => true).
        and_return(all_sched_maints)
      sched_maints_2 = double('sched_maints_2')
      sched_maints_2.should_receive(:intersect_range).
        with(start.to_i, start.to_i, :by_score => true).
        and_return(all_sched_maints_2)

      entity_check.should_receive(:scheduled_maintenances_by_start).and_return(sched_maints)
      entity_check_2.should_receive(:scheduled_maintenances_by_start).and_return(sched_maints_2)

      entity_check.should_receive(:end_scheduled_maintenance).with(sched_maint, an_instance_of(Fixnum))
      entity_check_2.should_receive(:end_scheduled_maintenance).with(sched_maint_2, an_instance_of(Fixnum))

      delete "/scheduled_maintenances", :check => {entity_name => [check, 'foo']}, :start_time => start.iso8601
      last_response.status.should == 204
    end

    it "returns a list of scheduled maintenance periods for an entity" do
      result = [{:entity => entity_name, :check => check, :scheduled_maintenances => json_data}]

      entity_presenter.should_receive(:scheduled_maintenances).with(nil, nil).and_return(result)

      Flapjack::Gateways::API::EntityPresenter.should_receive(:new).
        with(entity).and_return(entity_presenter)

      Flapjack::Data::Entity.should_receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      get "/scheduled_maintenances", :entity => entity_name
      last_response.should be_ok
      last_response.body.should == result.to_json
    end

    it "returns a list of scheduled maintenance periods within a time window for an entity" do
      start  = Time.parse('1 Jan 2012')
      finish = Time.parse('6 Jan 2012')

      result = [{:entity => entity_name, :check => check, :scheduled_maintenances => json_data}]

      entity_presenter.should_receive(:scheduled_maintenances).with(start.to_i, finish.to_i).and_return(result)

      Flapjack::Gateways::API::EntityPresenter.should_receive(:new).
        with(entity).and_return(entity_presenter)

      Flapjack::Data::Entity.should_receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      get "/scheduled_maintenances", :entity => entity_name,
        :start_time => start.iso8601, :end_time => finish.iso8601
      last_response.should be_ok
      last_response.body.should == result.to_json
    end

    it "returns a list of scheduled maintenance periods for a check on an entity" do
      result = [{:entity => entity_name, :check => check, :scheduled_maintenances => json_data}]

      entity_check_presenter.should_receive(:scheduled_maintenances).with(nil, nil).and_return(json_data)

      Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
        with(entity_check).and_return(entity_check_presenter)

      Flapjack::Data::Check.should_receive(:intersect).
        with(:entity_name => entity_name, :name => check).and_return(all_entity_checks)

      get "/scheduled_maintenances", :check => {entity_name => check}
      last_response.should be_ok
      last_response.body.should == result.to_json
    end

    it "returns a list of unscheduled maintenance periods for an entity" do
      result = [{:entity => entity_name, :check => check, :unscheduled_maintenances => json_data}]

      entity_presenter.should_receive(:unscheduled_maintenances).with(nil, nil).and_return(result)

      Flapjack::Gateways::API::EntityPresenter.should_receive(:new).
        with(entity).and_return(entity_presenter)

      Flapjack::Data::Entity.should_receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      get "/unscheduled_maintenances", :entity => entity_name
      last_response.should be_ok
      last_response.body.should == result.to_json
    end

    it "returns a list of unscheduled maintenance periods for a check on an entity" do
      result = [{:entity => entity_name, :check => check, :unscheduled_maintenances => json_data}]

      entity_check_presenter.should_receive(:unscheduled_maintenances).with(nil, nil).and_return(json_data)

      Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
        with(entity_check).and_return(entity_check_presenter)

      Flapjack::Data::Check.should_receive(:intersect).
        with(:entity_name => entity_name, :name => check).and_return(all_entity_checks)

      get "/unscheduled_maintenances", :check => {entity_name => check}
      last_response.should be_ok
      last_response.body.should == result.to_json
    end

    it "returns a list of unscheduled maintenance periods within a time window for a check an entity" do
      start  = Time.parse('1 Jan 2012')
      finish = Time.parse('6 Jan 2012')

      result = [{:entity => entity_name, :check => check, :unscheduled_maintenances => json_data}]

      entity_check_presenter.should_receive(:unscheduled_maintenances).with(start.to_i, finish.to_i).and_return(json_data)

      Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
        with(entity_check).and_return(entity_check_presenter)

      Flapjack::Data::Check.should_receive(:intersect).
        with(:entity_name => entity_name, :name => check).and_return(all_entity_checks)

      get "/unscheduled_maintenances", :check => {entity_name => check},
        :start_time => start.iso8601, :end_time => finish.iso8601
      last_response.should be_ok
      last_response.body.should == result.to_json
    end

    it "returns a list of outages, for one whole entity and two checks on another entity" do
      json_data_2 = {'other' => 'data'}
      json_data_3 = {'more' => 'data'}

      entity_2_name = 'entity_2'
      entity_2 = double(Flapjack::Data::Entity)

      result = [{:entity => entity_name,   :check => check, :outages => json_data},
                {:entity => entity_2_name, :check => 'foo', :outages => json_data_2},
                {:entity => entity_2_name, :check => 'bar', :outages => json_data_3}]

      foo_check = double(Flapjack::Data::Check)
      all_foo_checks = double('all_foo_checks', :all => [foo_check])
      bar_check = double(Flapjack::Data::Check)
      all_bar_checks = double('all_bar_checks', :all => [bar_check])

      foo_check_presenter = double(Flapjack::Gateways::API::EntityCheckPresenter)
      bar_check_presenter = double(Flapjack::Gateways::API::EntityCheckPresenter)

      entity_presenter.should_receive(:outages).with(nil, nil).and_return(result[0])
      foo_check_presenter.should_receive(:outages).with(nil, nil).and_return(json_data_2)
      bar_check_presenter.should_receive(:outages).with(nil, nil).and_return(json_data_3)

      Flapjack::Gateways::API::EntityPresenter.should_receive(:new).
        with(entity).and_return(entity_presenter)

      Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
        with(foo_check).and_return(foo_check_presenter)
      Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
        with(bar_check).and_return(bar_check_presenter)

      Flapjack::Data::Entity.should_receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      Flapjack::Data::Check.should_receive(:intersect).
        with(:entity_name => entity_2_name, :name => 'foo').and_return(all_foo_checks)
      Flapjack::Data::Check.should_receive(:intersect).
        with(:entity_name => entity_2_name, :name => 'bar').and_return(all_bar_checks)

      get "/outages", :entity => entity_name, :check => {entity_2_name => ['foo', 'bar']}
      last_response.should be_ok
      last_response.body.should == result.to_json
    end

    it "returns a list of outages for a check on an entity" do
      result = [{:entity => entity_name, :check => check, :outages => json_data}]

      entity_check_presenter.should_receive(:outages).with(nil, nil).and_return(json_data)

      Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
        with(entity_check).and_return(entity_check_presenter)

      Flapjack::Data::Check.should_receive(:intersect).
        with(:entity_name => entity_name, :name => check).and_return(all_entity_checks)

      get "/outages", :check => {entity_name => check}
      last_response.should be_ok
      last_response.body.should == result.to_json
    end

    it "returns a list of downtimes for an entity" do
      result = [{:entity => entity_name, :check => check, :downtime => json_data}]

      entity_presenter.should_receive(:downtime).with(nil, nil).and_return(result)

      Flapjack::Gateways::API::EntityPresenter.should_receive(:new).
        with(entity).and_return(entity_presenter)

      Flapjack::Data::Entity.should_receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      get "/downtime", :entity => entity_name
      last_response.should be_ok
      last_response.body.should == result.to_json
    end

    it "returns a list of downtimes for a check on an entity" do
      result = [{:entity => entity_name, :check => check, :downtime => json_data}]

      entity_check_presenter.should_receive(:downtime).with(nil, nil).and_return(json_data)

      Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
        with(entity_check).and_return(entity_check_presenter)

      Flapjack::Data::Check.should_receive(:intersect).
        with(:entity_name => entity_name, :name => check).and_return(all_entity_checks)

      get "/downtime", :check => {entity_name => check}
      last_response.should be_ok
      last_response.body.should == result.to_json
    end

    it "creates test notification events for all checks on an entity" do
      entity.should_receive(:check_list).and_return([check, 'foo'])
      entity.should_receive(:name).twice.and_return(entity_name)
      Flapjack::Data::Entity.should_receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      entity_check.should_receive(:entity).and_return(entity)
      entity_check.should_receive(:entity_name).and_return(entity_name)
      entity_check.should_receive(:check).and_return(check)

      Flapjack::Data::Check.should_receive(:intersect).
        with(:entity_name => entity_name, :name => check).and_return(all_entity_checks)

      entity_check_2 = double(Flapjack::Data::Check)
      entity_check_2.should_receive(:entity).and_return(entity)
      entity_check_2.should_receive(:entity_name).and_return(entity_name)
      entity_check_2.should_receive(:check).and_return('foo')

      all_entity_checks_2 = double('all_entity_checks_2', :all => [entity_check_2])
      Flapjack::Data::Check.should_receive(:intersect).
        with(:entity_name => entity_name, :name => 'foo').and_return(all_entity_checks_2)

      Flapjack::Data::Event.should_receive(:test_notifications).
        with('events', entity_name, check, an_instance_of(Hash))

      Flapjack::Data::Event.should_receive(:test_notifications).
        with('events', entity_name, 'foo', an_instance_of(Hash))

      post '/test_notifications', :entity => entity_name
      last_response.status.should == 204
    end

    it "creates a test notification event for check on an entity" do
      entity.should_receive(:name).and_return(entity_name)
      entity_check.should_receive(:entity).and_return(entity)
      entity_check.should_receive(:entity_name).and_return(entity_name)
      entity_check.should_receive(:check).and_return(check)
      Flapjack::Data::Check.should_receive(:intersect).
        with(:entity_name => entity_name, :name => check).and_return(all_entity_checks)

      Flapjack::Data::Event.should_receive(:test_notifications).
      with('events', entity_name, check, an_instance_of(Hash))

      post '/test_notifications', :check => {entity_name => check}
      last_response.status.should == 204
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

      Flapjack::Data::Entity.should_receive(:intersect).
        with(:name => 'clientx-app-01').and_return(no_entities)
      Flapjack::Data::Entity.should_receive(:intersect).
        with(:name => 'clientx-app-02').and_return(no_entities)

      Flapjack::Data::Contact.should_receive(:find_by_id).exactly(4).times.and_return(nil)

      entity.should_receive(:valid?).and_return(true)
      entity.should_receive(:save).and_return(true)
      entity.should_receive(:id).and_return('10001')

      entity_2 = double(Flapjack::Data::Entity)
      entity_2.should_receive(:valid?).and_return(true)
      entity_2.should_receive(:save).and_return(true)
      entity_2.should_receive(:id).and_return('10002')

      Flapjack::Data::Entity.should_receive(:new).
        with(:id => '10001', :name => 'clientx-app-01', :enabled => false).
        and_return(entity)
      Flapjack::Data::Entity.should_receive(:new).
        with(:id => '10002', :name => 'clientx-app-02', :enabled => false).
        and_return(entity_2)

      post "/entities", entities.to_json, {'CONTENT_TYPE' => 'application/json'}
      last_response.status.should == 204
    end

    it "does not create entities if the data is improperly formatted" do
      Flapjack::Data::Entity.should_not_receive(:new)

      post "/entities", {'entities' => ["Hello", "there"]}.to_json,
        {'CONTENT_TYPE' => 'application/json'}
      last_response.status.should == 403
    end

  end

  context "tags" do

    it "sets a single tag on an entity and returns current tags" do
      tags = ['web']
      entity.should_receive(:tags=).with(Set.new(tags))
      entity.should_receive(:tags).twice.and_return(Set.new, Set.new(tags))
      entity.should_receive(:save).and_return(true)
      Flapjack::Data::Entity.should_receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      post "entities/#{entity_name}/tags", :tag => tags.first
      last_response.should be_ok
      last_response.body.should be_json_eql( tags.to_json )
    end

    it "does not set a single tag on an entity that's not found" do
      Flapjack::Data::Entity.should_receive(:intersect).
        with(:name => entity_name).and_return(no_entities)

      post "entities/#{entity_name}/tags", :tag => 'web'
      last_response.should be_forbidden
    end

    it "sets multiple tags on an entity and returns current tags" do
      tags = ['web', 'app']
      entity.should_receive(:tags=).with(Set.new(tags))
      entity.should_receive(:tags).twice.and_return(Set.new, Set.new(tags))
      entity.should_receive(:save).and_return(true)
      Flapjack::Data::Entity.should_receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      # NB submitted at a lower level as tag[]=web&tag[]=app
      post "entities/#{entity_name}/tags", :tag => tags
      last_response.should be_ok
      last_response.body.should be_json_eql( tags.to_json )
    end

    it "does not set multiple tags on an entity that's not found" do
      Flapjack::Data::Entity.should_receive(:intersect).
        with(:name => entity_name).and_return(no_entities)

      post "entities/#{entity_name}/tags", :tag => ['web', 'app']
      last_response.should be_forbidden
    end

    it "removes a single tag from an entity" do
      tags = ['web']
      entity.should_receive(:tags=).with(Set.new)
      entity.should_receive(:tags).and_return(Set.new(tags))
      entity.should_receive(:save).and_return(true)
      Flapjack::Data::Entity.should_receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      delete "entities/#{entity_name}/tags", :tag => tags.first
      last_response.status.should == 204
    end

    it "does not remove a single tag from an entity that's not found" do
      Flapjack::Data::Entity.should_receive(:intersect).
        with(:name => entity_name).and_return(no_entities)

      delete "entities/#{entity_name}/tags", :tag => 'web'
      last_response.should be_forbidden
    end

    it "removes multiple tags from an entity" do
      tags = ['web', 'app']
      entity.should_receive(:tags=).with(Set.new)
      entity.should_receive(:tags).and_return(Set.new(tags))
      entity.should_receive(:save).and_return(true)
      Flapjack::Data::Entity.should_receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      delete "entities/#{entity_name}/tags", :tag => tags
      last_response.status.should == 204
    end

    it "does not remove multiple tags from an entity that's not found" do
      Flapjack::Data::Entity.should_receive(:intersect).
        with(:name => entity_name).and_return(no_entities)

      delete "entities/#{entity_name}/tags", :tag => ['web', 'app']
      last_response.should be_forbidden
    end

    it "gets all tags on an entity" do
      entity.should_receive(:tags).and_return(Set.new(['web', 'app']))

      Flapjack::Data::Entity.should_receive(:intersect).
        with(:name => entity_name).and_return(all_entities)

      get "entities/#{entity_name}/tags"
      last_response.should be_ok
      last_response.body.should be_json_eql( ['web', 'app'].to_json )
    end

    it "does not get all tags on an entity that's not found" do
      Flapjack::Data::Entity.should_receive(:intersect).
        with(:name => entity_name).and_return(no_entities)

      get "entities/#{entity_name}/tags"
      last_response.should be_forbidden
    end

  end

end
