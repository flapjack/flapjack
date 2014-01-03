require 'spec_helper'
require 'flapjack/gateways/api'

describe 'Flapjack::Gateways::API::EntityMethods', :sinatra => true, :logger => true do

  def app
    Flapjack::Gateways::API
  end

  let(:entity)          { double(Flapjack::Data::Entity) }
  let(:entity_check)    { double(Flapjack::Data::EntityCheck) }

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
    expect(Flapjack::RedisPool).to receive(:new).and_return(redis)
    Flapjack::Gateways::API.instance_variable_set('@config', {})
    Flapjack::Gateways::API.instance_variable_set('@logger', @logger)
    Flapjack::Gateways::API.start
  end

  it "returns a list of checks for an entity" do
    expect(entity).to receive(:check_list).and_return([check])
    expect(Flapjack::Data::Entity).to receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    aget "/checks/#{entity_name_esc}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq([check].to_json)
  end

  context 'non-bulk API calls' do

    it "returns the status for all checks on an entity" do
      status = double('status', :to_json => 'status!'.to_json)
      result = {:entity => entity_name, :check => check, :status => status}
      expect(entity_presenter).to receive(:status).and_return(result)

      expect(Flapjack::Gateways::API::EntityPresenter).to receive(:new).
        with(entity, :redis => redis).and_return(entity_presenter)

      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      aget "/status/#{entity_name_esc}"
      expect(last_response).to be_ok
      expect(last_response.body).to eq(['status!'].to_json)
    end

    it "should not show the status for an entity that's not found" do
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(nil)

      aget "/status/#{entity_name_esc}"
      expect(last_response).to be_forbidden
    end

    it "returns the status for a check on an entity" do
      status = double('status', :to_json => 'status!'.to_json)
      expect(entity_check_presenter).to receive(:status).and_return(status)

      expect(Flapjack::Gateways::API::EntityCheckPresenter).to receive(:new).
        with(entity_check).and_return(entity_check_presenter)

      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      aget "/status/#{entity_name_esc}/#{check}"
      expect(last_response).to be_ok
      expect(last_response.body).to eq('status!'.to_json)
    end

    it "should not show the status for a check on an entity that's not found" do
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(nil)

      aget "/status/#{entity_name_esc}/#{check}"
      expect(last_response).to be_forbidden
    end

    it "should not show the status for a check that's not found on an entity" do
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity, check, :redis => redis).and_return(nil)

      aget "/status/#{entity_name_esc}/#{check}"
      expect(last_response).to be_forbidden
    end

    it "returns a list of scheduled maintenance periods for an entity" do
      sched = double('sched', :to_json => 'sched!'.to_json)
      result = {:entity => entity_name, :check => check, :scheduled_maintenances => sched}
      expect(entity_presenter).to receive(:scheduled_maintenances).with(nil, nil).and_return(result)
      expect(Flapjack::Gateways::API::EntityPresenter).to receive(:new).
        with(entity, :redis => redis).and_return(entity_presenter)
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      aget "/scheduled_maintenances/#{entity_name_esc}"
      expect(last_response).to be_ok
      expect(last_response.body).to eq([{:check => check, :scheduled_maintenance => sched}].to_json)
    end

    it "returns a list of scheduled maintenance periods within a time window for an entity" do
      start  = Time.parse('1 Jan 2012')
      finish = Time.parse('6 Jan 2012')

      sched = double('sched', :to_json => 'sched!'.to_json)
      result = {:entity => entity_name, :check => check, :scheduled_maintenances => sched}
      expect(entity_presenter).to receive(:scheduled_maintenances).with(start.to_i, finish.to_i).and_return(result)
      expect(Flapjack::Gateways::API::EntityPresenter).to receive(:new).
        with(entity, :redis => redis).and_return(entity_presenter)
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      aget "/scheduled_maintenances/#{entity_name_esc}?" +
        "start_time=#{CGI.escape(start.iso8601)}&end_time=#{CGI.escape(finish.iso8601)}"
      expect(last_response).to be_ok
      expect(last_response.body).to eq([{:check => check, :scheduled_maintenance => sched}].to_json)
    end

    it "returns a list of scheduled maintenance periods for a check on an entity" do
      sched = double('sched', :to_json => 'sched!'.to_json)
      expect(entity_check_presenter).to receive(:scheduled_maintenances).with(nil, nil).and_return(sched)
      expect(Flapjack::Gateways::API::EntityCheckPresenter).to receive(:new).
        with(entity_check).and_return(entity_check_presenter)
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)
      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      aget "/scheduled_maintenances/#{entity_name_esc}/#{check}"
      expect(last_response).to be_ok
      expect(last_response.body).to eq('sched!'.to_json)
    end

    it "creates an acknowledgement for an entity check" do
      expect(entity_check).to receive(:entity_name).and_return(entity_name)
      expect(entity_check).to receive(:check).and_return(check)

      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)
      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)
      expect(Flapjack::Data::Event).to receive(:create_acknowledgement).
        with(entity_name, check, :summary => nil, :duration => (4 * 60 * 60), :redis => redis)

      apost "/acknowledgements/#{entity_name_esc}/#{check}"
      expect(last_response.status).to eq(204)
    end

    it "returns a list of unscheduled maintenance periods for an entity" do
      unsched = double('unsched', :to_json => 'unsched!'.to_json)
      result = {:entity => entity_name, :check => check, :unscheduled_maintenances => unsched}
      expect(entity_presenter).to receive(:unscheduled_maintenances).with(nil, nil).and_return(result)
      expect(Flapjack::Gateways::API::EntityPresenter).to receive(:new).
        with(entity, :redis => redis).and_return(entity_presenter)
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      aget "/unscheduled_maintenances/#{entity_name_esc}"
      expect(last_response).to be_ok
      expect(last_response.body).to eq([{:check => check, :unscheduled_maintenance => unsched}].to_json)
    end

    it "returns a list of unscheduled maintenance periods for a check on an entity" do
      unsched = double('unsched', :to_json => 'unsched!'.to_json)
      expect(entity_check_presenter).to receive(:unscheduled_maintenances).with(nil, nil).and_return(unsched)
      expect(Flapjack::Gateways::API::EntityCheckPresenter).to receive(:new).
        with(entity_check).and_return(entity_check_presenter)
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)
      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      aget "/unscheduled_maintenances/#{entity_name_esc}/#{check}"
      expect(last_response).to be_ok
      expect(last_response.body).to eq('unsched!'.to_json)
    end

    it "returns a list of unscheduled maintenance periods within a time window for a check an entity" do
      start    = Time.parse('1 Jan 2012')
      finish   = Time.parse('6 Jan 2012')

      unsched = double('unsched', :to_json => 'unsched!'.to_json)
      expect(entity_check_presenter).to receive(:unscheduled_maintenances).with(start.to_i, finish.to_i).and_return(unsched)
      expect(Flapjack::Gateways::API::EntityCheckPresenter).to receive(:new).
        with(entity_check).and_return(entity_check_presenter)
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)
      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      aget "/unscheduled_maintenances/#{entity_name_esc}/#{check}" +
        "?start_time=#{CGI.escape(start.iso8601)}&end_time=#{CGI.escape(finish.iso8601)}"
      expect(last_response).to be_ok
      expect(last_response.body).to eq('unsched!'.to_json)
    end

    it "returns a list of outages for an entity" do
      out = double('out', :to_json => 'out!'.to_json)
      result = {:entity => entity_name, :check => check, :outages => out}
      expect(entity_presenter).to receive(:outages).with(nil, nil).and_return(result)
      expect(Flapjack::Gateways::API::EntityPresenter).to receive(:new).
        with(entity, :redis => redis).and_return(entity_presenter)
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      aget "/outages/#{entity_name_esc}"
      expect(last_response).to be_ok
      expect(last_response.body).to eq([{:check => check, :outages => out}].to_json)
    end

    it "returns a list of outages for a check on an entity" do
      out = double('out', :to_json => 'out!'.to_json)
      expect(entity_check_presenter).to receive(:outages).with(nil, nil).and_return(out)
      expect(Flapjack::Gateways::API::EntityCheckPresenter).to receive(:new).
        with(entity_check).and_return(entity_check_presenter)
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)
      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      aget "/outages/#{entity_name_esc}/#{check}"
      expect(last_response).to be_ok
      expect(last_response.body).to eq('out!'.to_json)
    end

    it "returns a list of downtimes for an entity" do
      down = double('down', :to_json => 'down!'.to_json)
      result = {:entity => entity_name, :check => check, :downtime => down}
      expect(entity_presenter).to receive(:downtime).with(nil, nil).and_return(result)
      expect(Flapjack::Gateways::API::EntityPresenter).to receive(:new).
        with(entity, :redis => redis).and_return(entity_presenter)
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      aget "/downtime/#{entity_name_esc}"
      expect(last_response).to be_ok
      expect(last_response.body).to eq([{:check => check, :downtime => down}].to_json)
    end

    it "returns a list of downtimes for a check on an entity" do
      down = double('down', :to_json => 'down!'.to_json)
      expect(entity_check_presenter).to receive(:downtime).with(nil, nil).and_return(down)
      expect(Flapjack::Gateways::API::EntityCheckPresenter).to receive(:new).
        with(entity_check).and_return(entity_check_presenter)
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)
      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      aget "/downtime/#{entity_name_esc}/#{check}"
      expect(last_response).to be_ok
      expect(last_response.body).to eq('down!'.to_json)
    end

    it "creates a test notification event for check on an entity" do
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)
      expect(entity).to receive(:name).and_return(entity_name)
      expect(entity_check).to receive(:entity).and_return(entity)
      expect(entity_check).to receive(:entity_name).and_return(entity_name)
      expect(entity_check).to receive(:check).and_return('foo')
      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity, 'foo', :redis => redis).and_return(entity_check)

      expect(Flapjack::Data::Event).to receive(:test_notifications).
        with(entity_name, 'foo', hash_including(:redis => redis))

      apost "/test_notifications/#{entity_name_esc}/foo"
      expect(last_response.status).to eq(204)
    end

  end

  context 'bulk API calls' do

    it "returns the status for all checks on an entity" do
      status = double('status')
      result = [{:entity => entity_name, :check => check, :status => status}]
      expect(entity_presenter).to receive(:status).and_return(result)

      expect(Flapjack::Gateways::API::EntityPresenter).to receive(:new).
        with(entity, :redis => redis).and_return(entity_presenter)

      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      aget "/status", :entity => entity_name
      expect(last_response.body).to eq(result.to_json)
    end

    it "should not show the status for an entity that's not found" do
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(nil)

      aget "/status", :entity => entity_name
      expect(last_response).to be_forbidden
    end

    it "returns the status for a check on an entity" do
      status = double('status')
      result = [{:entity => entity_name, :check => check, :status => status}]
      expect(entity_check_presenter).to receive(:status).and_return(status)

      expect(Flapjack::Gateways::API::EntityCheckPresenter).to receive(:new).
        with(entity_check).and_return(entity_check_presenter)

      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      aget "/status", :check => {entity_name => check}
      expect(last_response).to be_ok
      expect(last_response.body).to eq(result.to_json)
    end

    it "should not show the status for a check on an entity that's not found" do
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(nil)

      aget "/status", :check => {entity_name => check}
      expect(last_response).to be_forbidden
    end

    it "should not show the status for a check that's not found on an entity" do
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity, check, :redis => redis).and_return(nil)

      aget "/status", :check => {entity_name => check}
      expect(last_response).to be_forbidden
    end

    it "creates an acknowledgement for an entity check" do
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)
      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      expect(entity_check).to receive(:entity_name).and_return(entity_name)
      expect(entity_check).to receive(:check).and_return(check)

      expect(Flapjack::Data::Event).to receive(:create_acknowledgement).
        with(entity_name, check, :summary => nil, :duration => (4 * 60 * 60), :redis => redis)

      apost '/acknowledgements',:check => {entity_name => check}
      expect(last_response.status).to eq(204)
    end

    it "deletes an unscheduled maintenance period for an entity check" do
      end_time = Time.now + (60 * 60) # an hour from now
      expect(entity_check).to receive(:end_unscheduled_maintenance).with(end_time.to_i)

      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      adelete "/unscheduled_maintenances", :check => {entity_name => check}, :end_time => end_time.iso8601
      expect(last_response.status).to eq(204)
    end

    it "creates a scheduled maintenance period for an entity check" do
      start = Time.now + (60 * 60) # an hour from now
      duration = (2 * 60 * 60)     # two hours
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)
      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)
      expect(entity_check).to receive(:create_scheduled_maintenance).
        with(start.getutc.to_i, duration, :summary => 'test')

      apost "/scheduled_maintenances/#{entity_name_esc}/#{check}?" +
         "start_time=#{CGI.escape(start.iso8601)}&summary=test&duration=#{duration}"
      expect(last_response.status).to eq(204)
    end

    it "doesn't create a scheduled maintenance period if the start time isn't passed" do
      duration = (2 * 60 * 60)     # two hours

      apost "/scheduled_maintenances/#{entity_name_esc}/#{check}?" +
         "summary=test&duration=#{duration}"
      expect(last_response.status).to eq(403)
    end

    it "deletes a scheduled maintenance period for an entity check" do
      start_time = Time.now + (60 * 60) # an hour from now
      expect(entity_check).to receive(:end_scheduled_maintenance).with(start_time.to_i)

      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      adelete "/scheduled_maintenances", :check => {entity_name => check}, :start_time => start_time.iso8601
      expect(last_response.status).to eq(204)
    end

    it "doesn't delete a scheduled maintenance period if the start time isn't passed" do
      expect(entity_check).not_to receive(:end_scheduled_maintenance)

      adelete "/scheduled_maintenances", :check => {entity_name => check}
      expect(last_response.status).to eq(403)
    end

    it "deletes scheduled maintenance periods for multiple entity checks" do
      start_time = Time.now + (60 * 60) # an hour from now

      entity_check_2 = double(Flapjack::Data::EntityCheck)

      expect(entity_check).to receive(:end_scheduled_maintenance).with(start_time.to_i)
      expect(entity_check_2).to receive(:end_scheduled_maintenance).with(start_time.to_i)

      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)
      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity, 'foo', :redis => redis).and_return(entity_check_2)

      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      adelete "/scheduled_maintenances", :check => {entity_name => [check, 'foo']}, :start_time => start_time.iso8601
      expect(last_response.status).to eq(204)
    end

    it "returns a list of scheduled maintenance periods for an entity" do
      sm = double('sched_maint')
      result = [{:entity => entity_name, :check => check, :scheduled_maintenances => sm}]

      expect(entity_presenter).to receive(:scheduled_maintenances).with(nil, nil).and_return(result)

      expect(Flapjack::Gateways::API::EntityPresenter).to receive(:new).
        with(entity, :redis => redis).and_return(entity_presenter)

      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      aget "/scheduled_maintenances", :entity => entity_name
      expect(last_response).to be_ok
      expect(last_response.body).to eq(result.to_json)
    end

    it "returns a list of scheduled maintenance periods within a time window for an entity" do
      start  = Time.parse('1 Jan 2012')
      finish = Time.parse('6 Jan 2012')

      sm = double('sched_maint')
      result = [{:entity => entity_name, :check => check, :scheduled_maintenances => sm}]

      expect(entity_presenter).to receive(:scheduled_maintenances).with(start.to_i, finish.to_i).and_return(result)

      expect(Flapjack::Gateways::API::EntityPresenter).to receive(:new).
        with(entity, :redis => redis).and_return(entity_presenter)

      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      aget "/scheduled_maintenances", :entity => entity_name,
        :start_time => start.iso8601, :end_time => finish.iso8601
      expect(last_response).to be_ok
      expect(last_response.body).to eq(result.to_json)
    end

    it "returns a list of scheduled maintenance periods for a check on an entity" do
      sm = double('sched_maint')
      result = [{:entity => entity_name, :check => check, :scheduled_maintenances => sm}]

      expect(entity_check_presenter).to receive(:scheduled_maintenances).with(nil, nil).and_return(sm)

      expect(Flapjack::Gateways::API::EntityCheckPresenter).to receive(:new).
        with(entity_check).and_return(entity_check_presenter)

      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      aget "/scheduled_maintenances", :check => {entity_name => check}
      expect(last_response).to be_ok
      expect(last_response.body).to eq(result.to_json)
    end

    it "returns a list of unscheduled maintenance periods for an entity" do
      um = double('unsched_maint')
      result = [{:entity => entity_name, :check => check, :unscheduled_maintenances => um}]

      expect(entity_presenter).to receive(:unscheduled_maintenances).with(nil, nil).and_return(result)

      expect(Flapjack::Gateways::API::EntityPresenter).to receive(:new).
        with(entity, :redis => redis).and_return(entity_presenter)

      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      aget "/unscheduled_maintenances", :entity => entity_name
      expect(last_response).to be_ok
      expect(last_response.body).to eq(result.to_json)
    end

    it "returns a list of unscheduled maintenance periods for a check on an entity" do
      um = double('unsched_maint')
      result = [{:entity => entity_name, :check => check, :unscheduled_maintenances => um}]

      expect(entity_check_presenter).to receive(:unscheduled_maintenances).with(nil, nil).and_return(um)

      expect(Flapjack::Gateways::API::EntityCheckPresenter).to receive(:new).
        with(entity_check).and_return(entity_check_presenter)

      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      aget "/unscheduled_maintenances", :check => {entity_name => check}
      expect(last_response).to be_ok
      expect(last_response.body).to eq(result.to_json)
    end

    it "returns a list of unscheduled maintenance periods within a time window for a check an entity" do
      start  = Time.parse('1 Jan 2012')
      finish = Time.parse('6 Jan 2012')

      um = double('unsched_maint')
      result = [{:entity => entity_name, :check => check, :unscheduled_maintenances => um}]

      expect(entity_check_presenter).to receive(:unscheduled_maintenances).with(start.to_i, finish.to_i).and_return(um)

      expect(Flapjack::Gateways::API::EntityCheckPresenter).to receive(:new).
        with(entity_check).and_return(entity_check_presenter)

      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      aget "/unscheduled_maintenances", :check => {entity_name => check},
        :start_time => start.iso8601, :end_time => finish.iso8601
      expect(last_response).to be_ok
      expect(last_response.body).to eq(result.to_json)
    end

    it "returns a list of outages, for one whole entity and two checks on another entity" do
      outages_1 = double('outages_1')
      outages_2 = double('outages_2')
      outages_3 = double('outages_3')

      entity_2_name = 'entity_2'
      entity_2 = double(Flapjack::Data::Entity)

      result = [{:entity => entity_name,   :check => check, :outages => outages_1},
                {:entity => entity_2_name, :check => 'foo', :outages => outages_2},
                {:entity => entity_2_name, :check => 'bar', :outages => outages_3}]

      foo_check = double(Flapjack::Data::EntityCheck)
      bar_check = double(Flapjack::Data::EntityCheck)

      foo_check_presenter = double(Flapjack::Gateways::API::EntityCheckPresenter)
      bar_check_presenter = double(Flapjack::Gateways::API::EntityCheckPresenter)

      expect(entity_presenter).to receive(:outages).with(nil, nil).and_return(result[0])
      expect(foo_check_presenter).to receive(:outages).with(nil, nil).and_return(outages_2)
      expect(bar_check_presenter).to receive(:outages).with(nil, nil).and_return(outages_3)

      expect(Flapjack::Gateways::API::EntityPresenter).to receive(:new).
        with(entity, :redis => redis).and_return(entity_presenter)

      expect(Flapjack::Gateways::API::EntityCheckPresenter).to receive(:new).
        with(foo_check).and_return(foo_check_presenter)
      expect(Flapjack::Gateways::API::EntityCheckPresenter).to receive(:new).
        with(bar_check).and_return(bar_check_presenter)

      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_2_name, :redis => redis).and_return(entity_2)

      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity_2, 'foo', :redis => redis).and_return(foo_check)
      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity_2, 'bar', :redis => redis).and_return(bar_check)

      aget "/outages", :entity => entity_name, :check => {entity_2_name => ['foo', 'bar']}
      expect(last_response).to be_ok
      expect(last_response.body).to eq(result.to_json)
    end

    it "returns a list of outages for a check on an entity" do
      outages = double('outages')
      result = [{:entity => entity_name, :check => check, :outages => outages}]

      expect(entity_check_presenter).to receive(:outages).with(nil, nil).and_return(outages)

      expect(Flapjack::Gateways::API::EntityCheckPresenter).to receive(:new).
        with(entity_check).and_return(entity_check_presenter)

      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      aget "/outages", :check => {entity_name => check}
      expect(last_response).to be_ok
      expect(last_response.body).to eq(result.to_json)
    end

    it "returns a list of downtimes for an entity" do
      downtime = double('downtime')
      result = [{:entity => entity_name, :check => check, :downtime => downtime}]

      expect(entity_presenter).to receive(:downtime).with(nil, nil).and_return(result)

      expect(Flapjack::Gateways::API::EntityPresenter).to receive(:new).
        with(entity, :redis => redis).and_return(entity_presenter)

      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      aget "/downtime", :entity => entity_name
      expect(last_response).to be_ok
      expect(last_response.body).to eq(result.to_json)
    end

    it "returns a list of downtimes for a check on an entity" do
      downtime = double('downtime')
      result = [{:entity => entity_name, :check => check, :downtime => downtime}]

      expect(entity_check_presenter).to receive(:downtime).with(nil, nil).and_return(downtime)

      expect(Flapjack::Gateways::API::EntityCheckPresenter).to receive(:new).
        with(entity_check).and_return(entity_check_presenter)

      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      aget "/downtime", :check => {entity_name => check}
      expect(last_response).to be_ok
      expect(last_response.body).to eq(result.to_json)
    end

    it "creates test notification events for all checks on an entity" do
      expect(entity).to receive(:check_list).and_return([check, 'foo'])
      expect(entity).to receive(:name).twice.and_return(entity_name)
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      expect(entity_check).to receive(:entity).and_return(entity)
      expect(entity_check).to receive(:entity_name).and_return(entity_name)
      expect(entity_check).to receive(:check).and_return(check)

      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      entity_check_2 = double(Flapjack::Data::EntityCheck)
      expect(entity_check_2).to receive(:entity).and_return(entity)
      expect(entity_check_2).to receive(:entity_name).and_return(entity_name)
      expect(entity_check_2).to receive(:check).and_return('foo')

      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity, 'foo', :redis => redis).and_return(entity_check_2)

      expect(Flapjack::Data::Event).to receive(:test_notifications).
        with(entity_name, check, hash_including(:redis => redis))

      expect(Flapjack::Data::Event).to receive(:test_notifications).
        with(entity_name, 'foo', hash_including(:redis => redis))

      apost '/test_notifications', :entity => entity_name
      expect(last_response.status).to eq(204)
    end

    it "creates a test notification event for check on an entity" do
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)
      expect(entity).to receive(:name).and_return(entity_name)
      expect(entity_check).to receive(:entity).and_return(entity)
      expect(entity_check).to receive(:entity_name).and_return(entity_name)
      expect(entity_check).to receive(:check).and_return(check)
      expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
        with(entity, check, :redis => redis).and_return(entity_check)

      expect(Flapjack::Data::Event).to receive(:test_notifications).
        with(entity_name, check, hash_including(:redis => redis))

      apost '/test_notifications', :check => {entity_name => check}
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
      expect(Flapjack::Data::Entity).to receive(:add).twice

      apost "/entities", entities.to_json, {'CONTENT_TYPE' => 'application/json'}
      expect(last_response.status).to eq(204)
    end

    it "does not create entities if the data is improperly formatted" do
      expect(Flapjack::Data::Entity).not_to receive(:add)

      apost "/entities", {'entities' => ["Hello", "there"]}.to_json,
        {'CONTENT_TYPE' => 'application/json'}
      expect(last_response.status).to eq(403)
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
      expect(Flapjack::Data::Entity).to receive(:add)

      apost "/entities", entities.to_json, {'CONTENT_TYPE' => 'application/json'}
      expect(last_response.status).to eq(403)
    end

  end

  context "tags" do

    it "sets a single tag on an entity and returns current tags" do
      expect(entity).to receive(:add_tags).with('web')
      expect(entity).to receive(:tags).and_return(['web'])
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      apost "entities/#{entity_name}/tags", :tag => 'web'
      expect(last_response).to be_ok
      expect(last_response.body).to eq(['web'].to_json)
    end

    it "does not set a single tag on an entity that's not found" do
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(nil)

      apost "entities/#{entity_name}/tags", :tag => 'web'
      expect(last_response).to be_forbidden
    end

    it "sets multiple tags on an entity and returns current tags" do
      expect(entity).to receive(:add_tags).with('web', 'app')
      expect(entity).to receive(:tags).and_return(['web', 'app'])
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      # NB submitted at a lower level as tag[]=web&tag[]=app
      apost "entities/#{entity_name}/tags", :tag => ['web', 'app']
      expect(last_response).to be_ok
      expect(last_response.body).to eq(['web', 'app'].to_json)
    end

    it "does not set multiple tags on an entity that's not found" do
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(nil)

      apost "entities/#{entity_name}/tags", :tag => ['web', 'app']
      expect(last_response).to be_forbidden
    end

    it "removes a single tag from an entity" do
      expect(entity).to receive(:delete_tags).with('web')
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      adelete "entities/#{entity_name}/tags", :tag => 'web'
      expect(last_response.status).to eq(204)
    end

    it "does not remove a single tag from an entity that's not found" do
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(nil)

      adelete "entities/#{entity_name}/tags", :tag => 'web'
      expect(last_response).to be_forbidden
    end

    it "removes multiple tags from an entity" do
      expect(entity).to receive(:delete_tags).with('web', 'app')
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      adelete "entities/#{entity_name}/tags", :tag => ['web', 'app']
      expect(last_response.status).to eq(204)
    end

    it "does not remove multiple tags from an entity that's not found" do
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(nil)

      adelete "entities/#{entity_name}/tags", :tag => ['web', 'app']
      expect(last_response).to be_forbidden
    end

    it "gets all tags on an entity" do
      expect(entity).to receive(:tags).and_return(['web', 'app'])
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(entity)

      aget "entities/#{entity_name}/tags"
      expect(last_response).to be_ok
      expect(last_response.body).to eq(['web', 'app'].to_json)
    end

    it "does not get all tags on an entity that's not found" do
      expect(Flapjack::Data::Entity).to receive(:find_by_name).
        with(entity_name, :redis => redis).and_return(nil)

      aget "entities/#{entity_name}/tags"
      expect(last_response).to be_forbidden
    end

  end

end
