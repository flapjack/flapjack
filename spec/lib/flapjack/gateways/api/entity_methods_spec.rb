require 'spec_helper'
require 'flapjack/gateways/api'

describe 'Flapjack::Gateways::API::EntityMethods', :sinatra => true, :logger => true, :json => true do

  def app
    Flapjack::Gateways::API
  end

  let(:entity)          { mock(Flapjack::Data::Entity) }
  let(:entity_check)    { mock(Flapjack::Data::EntityCheck) }

  let(:entity_name)     { 'www.example.net'}
  let(:entity_name_esc) { URI.escape(entity_name) }
  let(:check)           { 'ping' }

  let(:entity_presenter)       { mock(Flapjack::Gateways::API::EntityPresenter) }
  let(:entity_check_presenter) { mock(Flapjack::Gateways::API::EntityCheckPresenter) }

  let(:redis)           { mock(::Redis) }

  before(:all) do
    Flapjack::Gateways::API.class_eval {
      set :raise_errors, true
    }
  end

  before(:each) do
    Redis.should_receive(:new).and_return(redis)
    Flapjack::Gateways::API.instance_variable_set('@config', {})
    Flapjack::Gateways::API.instance_variable_set('@logger', @logger)
    Flapjack::Gateways::API.start
  end

  it "returns a list of checks for an entity" do
    entity.should_receive(:check_list).and_return([check])
    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    get "/checks/#{entity_name_esc}"
    last_response.should be_ok
    last_response.body.should == [check].to_json
  end

  context 'non-bulk API calls' do

    it "returns the status for all checks on an entity" do
      status = mock('status', :to_json => 'status!'.to_json)
      result = {:entity => entity_name, :check => check, :status => status}
      entity_presenter.should_receive(:status).and_return(result)

      Flapjack::Gateways::API::EntityPresenter.should_receive(:new).
        with(entity, :redis => redis).and_return(entity_presenter)

      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      get "/status/#{entity_name_esc}"
      last_response.should be_ok
      last_response.body.should == ['status!'].to_json
    end

    it "should not show the status for an entity that's not found" do
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(nil)

      get "/status/#{entity_name_esc}"
      last_response.should be_forbidden
    end

    it "returns the status for a check on an entity" do
      status = mock('status', :to_json => 'status!'.to_json)
      entity_check_presenter.should_receive(:status).and_return(status)

      Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
        with(entity_check).and_return(entity_check_presenter)

      Flapjack::Data::EntityCheck.should_receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      get "/status/#{entity_name_esc}/#{check}"
      last_response.should be_ok
      last_response.body.should == 'status!'.to_json
    end

    it "should not show the status for a check on an entity that's not found" do
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(nil)

      get "/status/#{entity_name_esc}/#{check}"
      last_response.should be_forbidden
    end

    it "should not show the status for a check that's not found on an entity" do
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      Flapjack::Data::EntityCheck.should_receive(:for_entity).
        with(entity, check, :redis => redis).and_return(nil)

      get "/status/#{entity_name_esc}/#{check}"
      last_response.should be_forbidden
    end

    it "returns a list of scheduled maintenance periods for an entity" do
      sched = mock('sched', :to_json => 'sched!'.to_json)
      result = {:entity => entity_name, :check => check, :scheduled_maintenances => sched}
      entity_presenter.should_receive(:scheduled_maintenances).with(nil, nil).and_return(result)
      Flapjack::Gateways::API::EntityPresenter.should_receive(:new).
        with(entity, :redis => redis).and_return(entity_presenter)
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      get "/scheduled_maintenances/#{entity_name_esc}"
      last_response.should be_ok
      last_response.body.should == [{:check => check, :scheduled_maintenance => sched}].to_json
    end

    it "returns a list of scheduled maintenance periods within a time window for an entity" do
      start  = Time.parse('1 Jan 2012')
      finish = Time.parse('6 Jan 2012')

      sched = mock('sched', :to_json => 'sched!'.to_json)
      result = {:entity => entity_name, :check => check, :scheduled_maintenances => sched}
      entity_presenter.should_receive(:scheduled_maintenances).with(start.to_i, finish.to_i).and_return(result)
      Flapjack::Gateways::API::EntityPresenter.should_receive(:new).
        with(entity, :redis => redis).and_return(entity_presenter)
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      get "/scheduled_maintenances/#{entity_name_esc}?" +
        "start_time=#{CGI.escape(start.iso8601)}&end_time=#{CGI.escape(finish.iso8601)}"
      last_response.should be_ok
      last_response.body.should == [{:check => check, :scheduled_maintenance => sched}].to_json
    end

    it "returns a list of scheduled maintenance periods for a check on an entity" do
      sched = mock('sched', :to_json => 'sched!'.to_json)
      entity_check_presenter.should_receive(:scheduled_maintenances).with(nil, nil).and_return(sched)
      Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
        with(entity_check).and_return(entity_check_presenter)
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)
      Flapjack::Data::EntityCheck.should_receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      get "/scheduled_maintenances/#{entity_name_esc}/#{check}"
      last_response.should be_ok
      last_response.body.should == 'sched!'.to_json
    end

    it "creates an acknowledgement for an entity check" do
      entity_check.should_receive(:entity_name).and_return(entity_name)
      entity_check.should_receive(:check).and_return(check)

      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)
      Flapjack::Data::EntityCheck.should_receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)
      Flapjack::Data::Event.should_receive(:create_acknowledgement).
        with(entity_name, check, :summary => nil, :duration => (4 * 60 * 60), :redis => redis)

      post "/acknowledgements/#{entity_name_esc}/#{check}"
      last_response.status.should == 204
    end

    it "returns a list of unscheduled maintenance periods for an entity" do
      unsched = mock('unsched', :to_json => 'unsched!'.to_json)
      result = {:entity => entity_name, :check => check, :unscheduled_maintenances => unsched}
      entity_presenter.should_receive(:unscheduled_maintenances).with(nil, nil).and_return(result)
      Flapjack::Gateways::API::EntityPresenter.should_receive(:new).
        with(entity, :redis => redis).and_return(entity_presenter)
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      get "/unscheduled_maintenances/#{entity_name_esc}"
      last_response.should be_ok
      last_response.body.should == [{:check => check, :unscheduled_maintenance => unsched}].to_json
    end

    it "returns a list of unscheduled maintenance periods for a check on an entity" do
      unsched = mock('unsched', :to_json => 'unsched!'.to_json)
      entity_check_presenter.should_receive(:unscheduled_maintenances).with(nil, nil).and_return(unsched)
      Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
        with(entity_check).and_return(entity_check_presenter)
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)
      Flapjack::Data::EntityCheck.should_receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      get "/unscheduled_maintenances/#{entity_name_esc}/#{check}"
      last_response.should be_ok
      last_response.body.should == 'unsched!'.to_json
    end

    it "returns a list of unscheduled maintenance periods within a time window for a check an entity" do
      start    = Time.parse('1 Jan 2012')
      finish   = Time.parse('6 Jan 2012')

      unsched = mock('unsched', :to_json => 'unsched!'.to_json)
      entity_check_presenter.should_receive(:unscheduled_maintenances).with(start.to_i, finish.to_i).and_return(unsched)
      Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
        with(entity_check).and_return(entity_check_presenter)
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)
      Flapjack::Data::EntityCheck.should_receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      get "/unscheduled_maintenances/#{entity_name_esc}/#{check}" +
        "?start_time=#{CGI.escape(start.iso8601)}&end_time=#{CGI.escape(finish.iso8601)}"
      last_response.should be_ok
      last_response.body.should == 'unsched!'.to_json
    end

    it "returns a list of outages for an entity" do
      out = mock('out', :to_json => 'out!'.to_json)
      result = {:entity => entity_name, :check => check, :outages => out}
      entity_presenter.should_receive(:outages).with(nil, nil).and_return(result)
      Flapjack::Gateways::API::EntityPresenter.should_receive(:new).
        with(entity, :redis => redis).and_return(entity_presenter)
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      get "/outages/#{entity_name_esc}"
      last_response.should be_ok
      last_response.body.should == [{:check => check, :outages => out}].to_json
    end

    it "returns a list of outages for a check on an entity" do
      out = mock('out', :to_json => 'out!'.to_json)
      entity_check_presenter.should_receive(:outages).with(nil, nil).and_return(out)
      Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
        with(entity_check).and_return(entity_check_presenter)
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)
      Flapjack::Data::EntityCheck.should_receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      get "/outages/#{entity_name_esc}/#{check}"
      last_response.should be_ok
      last_response.body.should == 'out!'.to_json
    end

    it "returns a list of downtimes for an entity" do
      down = mock('down', :to_json => 'down!'.to_json)
      result = {:entity => entity_name, :check => check, :downtime => down}
      entity_presenter.should_receive(:downtime).with(nil, nil).and_return(result)
      Flapjack::Gateways::API::EntityPresenter.should_receive(:new).
        with(entity, :redis => redis).and_return(entity_presenter)
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      get "/downtime/#{entity_name_esc}"
      last_response.should be_ok
      last_response.body.should == [{:check => check, :downtime => down}].to_json
    end

    it "returns a list of downtimes for a check on an entity" do
      down = mock('down', :to_json => 'down!'.to_json)
      entity_check_presenter.should_receive(:downtime).with(nil, nil).and_return(down)
      Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
        with(entity_check).and_return(entity_check_presenter)
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)
      Flapjack::Data::EntityCheck.should_receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      get "/downtime/#{entity_name_esc}/#{check}"
      last_response.should be_ok
      last_response.body.should == 'down!'.to_json
    end

    it "creates a test notification event for check on an entity" do
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)
      entity.should_receive(:name).and_return(entity_name)
      entity_check.should_receive(:entity).and_return(entity)
      entity_check.should_receive(:entity_name).and_return(entity_name)
      entity_check.should_receive(:check).and_return('foo')
      Flapjack::Data::EntityCheck.should_receive(:for_entity).
        with(entity, 'foo', :redis => redis).and_return(entity_check)

      Flapjack::Data::Event.should_receive(:test_notifications).
        with(entity_name, 'foo', hash_including(:redis => redis))

      post "/test_notifications/#{entity_name_esc}/foo"
      last_response.status.should == 204
    end

  end

  context 'bulk API calls' do

    it "returns the status for all checks on an entity" do
      status = mock('status')
      result = [{:entity => entity_name, :check => check, :status => status}]
      entity_presenter.should_receive(:status).and_return(result)

      Flapjack::Gateways::API::EntityPresenter.should_receive(:new).
        with(entity, :redis => redis).and_return(entity_presenter)

      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      get "/status", :entity => entity_name
      last_response.body.should == result.to_json
    end

    it "should not show the status for an entity that's not found" do
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(nil)

      get "/status", :entity => entity_name
      last_response.should be_forbidden
    end

    it "returns the status for a check on an entity" do
      status = mock('status')
      result = [{:entity => entity_name, :check => check, :status => status}]
      entity_check_presenter.should_receive(:status).and_return(status)

      Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
        with(entity_check).and_return(entity_check_presenter)

      Flapjack::Data::EntityCheck.should_receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      get "/status", :check => {entity_name => check}
      last_response.should be_ok
      last_response.body.should == result.to_json
    end

    it "should not show the status for a check on an entity that's not found" do
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(nil)

      get "/status", :check => {entity_name => check}
      last_response.should be_forbidden
    end

    it "should not show the status for a check that's not found on an entity" do
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      Flapjack::Data::EntityCheck.should_receive(:for_entity).
        with(entity, check, :redis => redis).and_return(nil)

      get "/status", :check => {entity_name => check}
      last_response.should be_forbidden
    end

    it "creates an acknowledgement for an entity check" do
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)
      Flapjack::Data::EntityCheck.should_receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      entity_check.should_receive(:entity_name).and_return(entity_name)
      entity_check.should_receive(:check).and_return(check)

      Flapjack::Data::Event.should_receive(:create_acknowledgement).
        with(entity_name, check, :summary => nil, :duration => (4 * 60 * 60), :redis => redis)

      post '/acknowledgements',:check => {entity_name => check}
      last_response.status.should == 204
    end

    it "deletes an unscheduled maintenance period for an entity check" do
      end_time = Time.now + (60 * 60) # an hour from now
      entity_check.should_receive(:end_unscheduled_maintenance).with(end_time.to_i)

      Flapjack::Data::EntityCheck.should_receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      delete "/unscheduled_maintenances", :check => {entity_name => check}, :end_time => end_time.iso8601
      last_response.status.should == 204
    end

    it "creates a scheduled maintenance period for an entity check" do
      start = Time.now + (60 * 60) # an hour from now
      duration = (2 * 60 * 60)     # two hours
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)
      Flapjack::Data::EntityCheck.should_receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)
      entity_check.should_receive(:create_scheduled_maintenance).
        with(:summary => 'test', :duration => duration, :start_time => start.getutc.to_i)

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
      start_time = Time.now + (60 * 60) # an hour from now
      entity_check.should_receive(:end_scheduled_maintenance).with(start_time.to_i)

      Flapjack::Data::EntityCheck.should_receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      delete "/scheduled_maintenances", :check => {entity_name => check}, :start_time => start_time.iso8601
      last_response.status.should == 204
    end

    it "doesn't delete a scheduled maintenance period if the start time isn't passed" do
      entity_check.should_not_receive(:end_scheduled_maintenance)

      delete "/scheduled_maintenances", :check => {entity_name => check}
      last_response.status.should == 403
    end

    it "deletes scheduled maintenance periods for multiple entity checks" do
      start_time = Time.now + (60 * 60) # an hour from now

      entity_check_2 = mock(Flapjack::Data::EntityCheck)

      entity_check.should_receive(:end_scheduled_maintenance).with(start_time.to_i)
      entity_check_2.should_receive(:end_scheduled_maintenance).with(start_time.to_i)

      Flapjack::Data::EntityCheck.should_receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)
      Flapjack::Data::EntityCheck.should_receive(:for_entity).
        with(entity, 'foo', :redis => redis).and_return(entity_check_2)

      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      delete "/scheduled_maintenances", :check => {entity_name => [check, 'foo']}, :start_time => start_time.iso8601
      last_response.status.should == 204
    end

    it "returns a list of scheduled maintenance periods for an entity" do
      sm = mock('sched_maint')
      result = [{:entity => entity_name, :check => check, :scheduled_maintenances => sm}]

      entity_presenter.should_receive(:scheduled_maintenances).with(nil, nil).and_return(result)

      Flapjack::Gateways::API::EntityPresenter.should_receive(:new).
        with(entity, :redis => redis).and_return(entity_presenter)

      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      get "/scheduled_maintenances", :entity => entity_name
      last_response.should be_ok
      last_response.body.should == result.to_json
    end

    it "returns a list of scheduled maintenance periods within a time window for an entity" do
      start  = Time.parse('1 Jan 2012')
      finish = Time.parse('6 Jan 2012')

      sm = mock('sched_maint')
      result = [{:entity => entity_name, :check => check, :scheduled_maintenances => sm}]

      entity_presenter.should_receive(:scheduled_maintenances).with(start.to_i, finish.to_i).and_return(result)

      Flapjack::Gateways::API::EntityPresenter.should_receive(:new).
        with(entity, :redis => redis).and_return(entity_presenter)

      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      get "/scheduled_maintenances", :entity => entity_name,
        :start_time => start.iso8601, :end_time => finish.iso8601
      last_response.should be_ok
      last_response.body.should == result.to_json
    end

    it "returns a list of scheduled maintenance periods for a check on an entity" do
      sm = mock('sched_maint')
      result = [{:entity => entity_name, :check => check, :scheduled_maintenances => sm}]

      entity_check_presenter.should_receive(:scheduled_maintenances).with(nil, nil).and_return(sm)

      Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
        with(entity_check).and_return(entity_check_presenter)

      Flapjack::Data::EntityCheck.should_receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      get "/scheduled_maintenances", :check => {entity_name => check}
      last_response.should be_ok
      last_response.body.should == result.to_json
    end

    it "returns a list of unscheduled maintenance periods for an entity" do
      um = mock('unsched_maint')
      result = [{:entity => entity_name, :check => check, :unscheduled_maintenances => um}]

      entity_presenter.should_receive(:unscheduled_maintenances).with(nil, nil).and_return(result)

      Flapjack::Gateways::API::EntityPresenter.should_receive(:new).
        with(entity, :redis => redis).and_return(entity_presenter)

      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      get "/unscheduled_maintenances", :entity => entity_name
      last_response.should be_ok
      last_response.body.should == result.to_json
    end

    it "returns a list of unscheduled maintenance periods for a check on an entity" do
      um = mock('unsched_maint')
      result = [{:entity => entity_name, :check => check, :unscheduled_maintenances => um}]

      entity_check_presenter.should_receive(:unscheduled_maintenances).with(nil, nil).and_return(um)

      Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
        with(entity_check).and_return(entity_check_presenter)

      Flapjack::Data::EntityCheck.should_receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      get "/unscheduled_maintenances", :check => {entity_name => check}
      last_response.should be_ok
      last_response.body.should == result.to_json
    end

    it "returns a list of unscheduled maintenance periods within a time window for a check an entity" do
      start  = Time.parse('1 Jan 2012')
      finish = Time.parse('6 Jan 2012')

      um = mock('unsched_maint')
      result = [{:entity => entity_name, :check => check, :unscheduled_maintenances => um}]

      entity_check_presenter.should_receive(:unscheduled_maintenances).with(start.to_i, finish.to_i).and_return(um)

      Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
        with(entity_check).and_return(entity_check_presenter)

      Flapjack::Data::EntityCheck.should_receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      get "/unscheduled_maintenances", :check => {entity_name => check},
        :start_time => start.iso8601, :end_time => finish.iso8601
      last_response.should be_ok
      last_response.body.should == result.to_json
    end

    it "returns a list of outages, for one whole entity and two checks on another entity" do
      outages_1 = mock('outages_1')
      outages_2 = mock('outages_2')
      outages_3 = mock('outages_3')

      entity_2_name = 'entity_2'
      entity_2 = mock(Flapjack::Data::Entity)

      result = [{:entity => entity_name,   :check => check, :outages => outages_1},
                {:entity => entity_2_name, :check => 'foo', :outages => outages_2},
                {:entity => entity_2_name, :check => 'bar', :outages => outages_3}]

      foo_check = mock(Flapjack::Data::EntityCheck)
      bar_check = mock(Flapjack::Data::EntityCheck)

      foo_check_presenter = mock(Flapjack::Gateways::API::EntityCheckPresenter)
      bar_check_presenter = mock(Flapjack::Gateways::API::EntityCheckPresenter)

      entity_presenter.should_receive(:outages).with(nil, nil).and_return(result[0])
      foo_check_presenter.should_receive(:outages).with(nil, nil).and_return(outages_2)
      bar_check_presenter.should_receive(:outages).with(nil, nil).and_return(outages_3)

      Flapjack::Gateways::API::EntityPresenter.should_receive(:new).
        with(entity, :redis => redis).and_return(entity_presenter)

      Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
        with(foo_check).and_return(foo_check_presenter)
      Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
        with(bar_check).and_return(bar_check_presenter)

      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_2_name, :redis => redis).and_return(entity_2)

      Flapjack::Data::EntityCheck.should_receive(:for_entity).
        with(entity_2, 'foo', :redis => redis).and_return(foo_check)
      Flapjack::Data::EntityCheck.should_receive(:for_entity).
        with(entity_2, 'bar', :redis => redis).and_return(bar_check)

      get "/outages", :entity => entity_name, :check => {entity_2_name => ['foo', 'bar']}
      last_response.should be_ok
      last_response.body.should == result.to_json
    end

    it "returns a list of outages for a check on an entity" do
      outages = mock('outages')
      result = [{:entity => entity_name, :check => check, :outages => outages}]

      entity_check_presenter.should_receive(:outages).with(nil, nil).and_return(outages)

      Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
        with(entity_check).and_return(entity_check_presenter)

      Flapjack::Data::EntityCheck.should_receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      get "/outages", :check => {entity_name => check}
      last_response.should be_ok
      last_response.body.should == result.to_json
    end

    it "returns a list of downtimes for an entity" do
      downtime = mock('downtime')
      result = [{:entity => entity_name, :check => check, :downtime => downtime}]

      entity_presenter.should_receive(:downtime).with(nil, nil).and_return(result)

      Flapjack::Gateways::API::EntityPresenter.should_receive(:new).
        with(entity, :redis => redis).and_return(entity_presenter)

      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      get "/downtime", :entity => entity_name
      last_response.should be_ok
      last_response.body.should == result.to_json
    end

    it "returns a list of downtimes for a check on an entity" do
      downtime = mock('downtime')
      result = [{:entity => entity_name, :check => check, :downtime => downtime}]

      entity_check_presenter.should_receive(:downtime).with(nil, nil).and_return(downtime)

      Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
        with(entity_check).and_return(entity_check_presenter)

      Flapjack::Data::EntityCheck.should_receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      get "/downtime", :check => {entity_name => check}
      last_response.should be_ok
      last_response.body.should == result.to_json
    end

    it "creates test notification events for all checks on an entity" do
      entity.should_receive(:check_list).and_return([check, 'foo'])
      entity.should_receive(:name).twice.and_return(entity_name)
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      entity_check.should_receive(:entity).and_return(entity)
      entity_check.should_receive(:entity_name).and_return(entity_name)
      entity_check.should_receive(:check).and_return(check)

      Flapjack::Data::EntityCheck.should_receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      entity_check_2 = mock(Flapjack::Data::EntityCheck)
      entity_check_2.should_receive(:entity).and_return(entity)
      entity_check_2.should_receive(:entity_name).and_return(entity_name)
      entity_check_2.should_receive(:check).and_return('foo')

      Flapjack::Data::EntityCheck.should_receive(:for_entity).
        with(entity, 'foo', :redis => redis).and_return(entity_check_2)

      Flapjack::Data::Event.should_receive(:test_notifications).
        with(entity_name, check, hash_including(:redis => redis))

      Flapjack::Data::Event.should_receive(:test_notifications).
        with(entity_name, 'foo', hash_including(:redis => redis))


      post '/test_notifications', :entity => entity_name
      last_response.status.should == 204
    end

    it "creates a test notification event for check on an entity" do
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)
      entity.should_receive(:name).and_return(entity_name)
      entity_check.should_receive(:entity).and_return(entity)
      entity_check.should_receive(:entity_name).and_return(entity_name)
      entity_check.should_receive(:check).and_return(check)
      Flapjack::Data::EntityCheck.should_receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      Flapjack::Data::Event.should_receive(:test_notifications).
      with(entity_name, check, hash_including(:redis => redis))


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
      Flapjack::Data::Entity.should_receive(:add).twice

      post "/entities", entities.to_json, {'CONTENT_TYPE' => 'application/json'}
      last_response.status.should == 204
    end

    it "does not create entities if the data is improperly formatted" do
      Flapjack::Data::Entity.should_not_receive(:add)

      post "/entities", {'entities' => ["Hello", "there"]}.to_json,
        {'CONTENT_TYPE' => 'application/json'}
      last_response.status.should == 403
    end

    it "does not create entities if they don't contain an id" do
      entities = {'entities' =>
        [
         {"id" => "10001",
          "name" => "clientx-app-01",
          "contacts" => ["0362","0363","0364"]
         },
         {"name" => "clientx-app-02",
          "contacts" => ["0362"]
         }
        ]
      }
      Flapjack::Data::Entity.should_receive(:add)

      post "/entities", entities.to_json, {'CONTENT_TYPE' => 'application/json'}
      last_response.status.should == 403
    end

  end

  context "tags" do

    it "sets a single tag on an entity and returns current tags" do
      entity.should_receive(:add_tags).with('web')
      entity.should_receive(:tags).and_return(['web'])
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      post "entities/#{entity_name}/tags", :tag => 'web'
      last_response.should be_ok
      last_response.body.should be_json_eql( ['web'].to_json )
    end

    it "does not set a single tag on an entity that's not found" do
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(nil)

      post "entities/#{entity_name}/tags", :tag => 'web'
      last_response.should be_forbidden
    end

    it "sets multiple tags on an entity and returns current tags" do
      entity.should_receive(:add_tags).with('web', 'app')
      entity.should_receive(:tags).and_return(['web', 'app'])
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      # NB submitted at a lower level as tag[]=web&tag[]=app
      post "entities/#{entity_name}/tags", :tag => ['web', 'app']
      last_response.should be_ok
      last_response.body.should be_json_eql( ['web', 'app'].to_json )
    end

    it "does not set multiple tags on an entity that's not found" do
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(nil)

      post "entities/#{entity_name}/tags", :tag => ['web', 'app']
      last_response.should be_forbidden
    end

    it "removes a single tag from an entity" do
      entity.should_receive(:delete_tags).with('web')
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      delete "entities/#{entity_name}/tags", :tag => 'web'
      last_response.status.should == 204
    end

    it "does not remove a single tag from an entity that's not found" do
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(nil)

      delete "entities/#{entity_name}/tags", :tag => 'web'
      last_response.should be_forbidden
    end

    it "removes multiple tags from an entity" do
      entity.should_receive(:delete_tags).with('web', 'app')
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      delete "entities/#{entity_name}/tags", :tag => ['web', 'app']
      last_response.status.should == 204
    end

    it "does not remove multiple tags from an entity that's not found" do
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(nil)

      delete "entities/#{entity_name}/tags", :tag => ['web', 'app']
      last_response.should be_forbidden
    end

    it "gets all tags on an entity" do
      entity.should_receive(:tags).and_return(['web', 'app'])
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      get "entities/#{entity_name}/tags"
      last_response.should be_ok
      last_response.body.should be_json_eql( ['web', 'app'].to_json )
    end

    it "does not get all tags on an entity that's not found" do
      Flapjack::Data::Entity.should_receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(nil)

      get "entities/#{entity_name}/tags"
      last_response.should be_forbidden
    end

  end

end
