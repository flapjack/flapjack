require 'spec_helper'
require 'flapjack/api'

describe 'Flapjack::API', :sinatra => true do

  def app
    Flapjack::API
  end

  let(:entity)          { mock(Flapjack::Data::Entity) }
  let(:entity_check)    { mock(Flapjack::Data::EntityCheck) }

  let(:entity_name)     { 'example.com'}
  let(:entity_name_esc) { URI.escape(entity_name) }
  let(:check)           { 'ping' }

  let(:entity_presenter)       { mock(Flapjack::API::EntityPresenter) }
  let(:entity_check_presenter) { mock(Flapjack::API::EntityCheckPresenter) }

  let(:redis)           { mock(::Redis) }

  before(:each) do
    Flapjack::API.class_variable_set('@@redis', redis)
  end

  it "returns a list of checks for an entity" do
    check_list = ['ping']
    entity.should_receive(:check_list).and_return(check_list)
    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    get "/checks/#{entity_name_esc}"
    last_response.should be_ok
    last_response.body.should == check_list.to_json
  end

  it "returns a list of scheduled maintenance periods for an entity" do
    result = mock('result')
    result_json = %q{"result"}
    result.should_receive(:to_json).and_return(result_json)
    entity_presenter.should_receive(:scheduled_maintenance).with(nil, nil).and_return(result)
    Flapjack::API::EntityPresenter.should_receive(:new).
      with(entity, :redis => redis).and_return(entity_presenter)
    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    get "/scheduled_maintenances/#{entity_name_esc}"
    last_response.should be_ok
    last_response.body.should == result_json
  end

  it "returns a list of scheduled maintenance periods within a time window for an entity"

  it "returns a list of scheduled maintenance periods for a check on an entity" do
    result = mock('result')
    result_json = %q{"result"}
    result.should_receive(:to_json).and_return(result_json)
    entity_check_presenter.should_receive(:scheduled_maintenance).with(nil, nil).and_return(result)
    Flapjack::API::EntityCheckPresenter.should_receive(:new).
      with(entity_check).and_return(entity_check_presenter)
    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)
    Flapjack::Data::EntityCheck.should_receive(:for_entity).
      with(entity, check, :redis => redis).and_return(entity_check)

    get "/scheduled_maintenances/#{entity_name_esc}/#{check}"
    last_response.should be_ok
    last_response.body.should == result_json
  end

  it "returns a list of unscheduled maintenance periods for an entity" do
    result = mock('result')
    result_json = %q{"result"}
    result.should_receive(:to_json).and_return(result_json)
    entity_presenter.should_receive(:unscheduled_maintenance).with(nil, nil).and_return(result)
    Flapjack::API::EntityPresenter.should_receive(:new).
      with(entity, :redis => redis).and_return(entity_presenter)
    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    get "/unscheduled_maintenances/#{entity_name_esc}"
    last_response.should be_ok
    last_response.body.should == result_json
  end

  it "returns a list of unscheduled maintenance periods for a check on an entity" do
    result = mock('result')
    result_json = %q{"result"}
    result.should_receive(:to_json).and_return(result_json)
    entity_check_presenter.should_receive(:unscheduled_maintenance).with(nil, nil).and_return(result)
    Flapjack::API::EntityCheckPresenter.should_receive(:new).
      with(entity_check).and_return(entity_check_presenter)
    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)
    Flapjack::Data::EntityCheck.should_receive(:for_entity).
      with(entity, check, :redis => redis).and_return(entity_check)

    get "/unscheduled_maintenances/#{entity_name_esc}/#{check}"
    last_response.should be_ok
    last_response.body.should == result_json
  end


  it "returns a list of unscheduled maintenance periods within a time window for a check an entity"

  it "returns a list of outages for an entity" do
    result = mock('result')
    result_json = %q{"result"}
    result.should_receive(:to_json).and_return(result_json)
    entity_presenter.should_receive(:outages).with(nil, nil).and_return(result)
    Flapjack::API::EntityPresenter.should_receive(:new).
      with(entity, :redis => redis).and_return(entity_presenter)
    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    get "/outages/#{entity_name_esc}"
    last_response.should be_ok
    last_response.body.should == result_json
  end

  it "returns a list of outages for a check on an entity" do
    result = mock('result')
    result_json = %q{"result"}
    result.should_receive(:to_json).and_return(result_json)
    entity_check_presenter.should_receive(:outages).with(nil, nil).and_return(result)
    Flapjack::API::EntityCheckPresenter.should_receive(:new).
      with(entity_check).and_return(entity_check_presenter)
    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)
    Flapjack::Data::EntityCheck.should_receive(:for_entity).
      with(entity, check, :redis => redis).and_return(entity_check)

    get "/outages/#{entity_name_esc}/#{check}"
    last_response.should be_ok
    last_response.body.should == result_json
  end

  it "returns a list of downtimes for an entity" do
    result = mock('result')
    result_json = %q{"result"}
    result.should_receive(:to_json).and_return(result_json)
    entity_presenter.should_receive(:downtime).with(nil, nil).and_return(result)
    Flapjack::API::EntityPresenter.should_receive(:new).
      with(entity, :redis => redis).and_return(entity_presenter)
    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    get "/downtime/#{entity_name_esc}"
    last_response.should be_ok
    last_response.body.should == result_json
  end

  it "returns a list of downtimes for a check on an entity" do
    result = mock('result')
    result_json = %q{"result"}
    result.should_receive(:to_json).and_return(result_json)
    entity_check_presenter.should_receive(:downtime).with(nil, nil).and_return(result)
    Flapjack::API::EntityCheckPresenter.should_receive(:new).
      with(entity_check).and_return(entity_check_presenter)
    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)
    Flapjack::Data::EntityCheck.should_receive(:for_entity).
      with(entity, check, :redis => redis).and_return(entity_check)

    get "/downtime/#{entity_name_esc}/#{check}"
    last_response.should be_ok
    last_response.body.should == result_json
  end

end