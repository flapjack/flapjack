require 'spec_helper'
require 'flapjack/gateways/api'
require 'json_spec'

describe 'Flapjack::Gateways::API', :sinatra => true, :logger => true do

  def app
    Flapjack::Gateways::API
  end

  let(:entity)          { mock(Flapjack::Data::Entity) }
  let(:entity_check)    { mock(Flapjack::Data::EntityCheck) }

  let(:entity_name)     { 'www.example.net'}
  let(:entity_name_esc) { URI.escape(entity_name) }
  let(:check)           { 'ping' }

  let(:contact)         { mock(Flapjack::Data::Contact) }
  let(:contact_id)      { '21' }
  let(:contact_media_list) { [ 'email', 'sms' ] }

  let(:entity_presenter)       { mock(Flapjack::Gateways::API::EntityPresenter) }
  let(:entity_check_presenter) { mock(Flapjack::Gateways::API::EntityCheckPresenter) }

  let(:redis)           { mock(::Redis) }

  before(:each) do
    Flapjack::RedisPool.should_receive(:new).and_return(redis)
    Flapjack::Gateways::API.instance_variable_set('@config', {})
    Flapjack::Gateways::API.instance_variable_set('@logger', @logger)
    Flapjack::Gateways::API.start
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
    Flapjack::Gateways::API::EntityPresenter.should_receive(:new).
      with(entity, :redis => redis).and_return(entity_presenter)
    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    get "/scheduled_maintenances/#{entity_name_esc}"
    last_response.should be_ok
    last_response.body.should == result_json
  end

  it "creates an acknowledgement for an entity check" do
    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)
    Flapjack::Data::EntityCheck.should_receive(:for_entity).
      with(entity, check, :redis => redis).and_return(entity_check)
    entity_check.should_receive(:create_acknowledgement).with('summary' => nil, 'duration' => (4 * 60 * 60))

    post "/acknowledgements/#{entity_name_esc}/#{check}"
    last_response.status.should == 204
  end

  it "returns a list of scheduled maintenance periods within a time window for an entity" do
    start  = Time.parse('1 Jan 2012')
    finish = Time.parse('6 Jan 2012')

    result = mock('result')
    result_json = %q{"result"}
    result.should_receive(:to_json).and_return(result_json)
    entity_presenter.should_receive(:scheduled_maintenance).with(start.to_i, finish.to_i).and_return(result)
    Flapjack::Gateways::API::EntityPresenter.should_receive(:new).
      with(entity, :redis => redis).and_return(entity_presenter)
    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    get "/scheduled_maintenances/#{entity_name_esc}?" +
      "start_time=#{CGI.escape(start.iso8601)}&end_time=#{CGI.escape(finish.iso8601)}"
    last_response.should be_ok
    last_response.body.should == result_json
  end

  it "returns a list of scheduled maintenance periods for a check on an entity" do
    result = mock('result')
    result_json = %q{"result"}
    result.should_receive(:to_json).and_return(result_json)
    entity_check_presenter.should_receive(:scheduled_maintenance).with(nil, nil).and_return(result)
    Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
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
    Flapjack::Gateways::API::EntityPresenter.should_receive(:new).
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
    Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
      with(entity_check).and_return(entity_check_presenter)
    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)
    Flapjack::Data::EntityCheck.should_receive(:for_entity).
      with(entity, check, :redis => redis).and_return(entity_check)

    get "/unscheduled_maintenances/#{entity_name_esc}/#{check}"
    last_response.should be_ok
    last_response.body.should == result_json
  end

  it "returns a list of unscheduled maintenance periods within a time window for a check an entity" do
    start    = Time.parse('1 Jan 2012')
    finish   = Time.parse('6 Jan 2012')

    result = mock('result')
    result_json = %q{"result"}
    result.should_receive(:to_json).and_return(result_json)
    entity_check_presenter.should_receive(:unscheduled_maintenance).with(start.to_i, finish.to_i).and_return(result)
    Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
      with(entity_check).and_return(entity_check_presenter)
    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)
    Flapjack::Data::EntityCheck.should_receive(:for_entity).
      with(entity, check, :redis => redis).and_return(entity_check)

    get "/unscheduled_maintenances/#{entity_name_esc}/#{check}" +
      "?start_time=#{CGI.escape(start.iso8601)}&end_time=#{CGI.escape(finish.iso8601)}"
    last_response.should be_ok
    last_response.body.should == result_json
  end

  it "returns a list of outages for an entity" do
    result = mock('result')
    result_json = %q{"result"}
    result.should_receive(:to_json).and_return(result_json)
    entity_presenter.should_receive(:outages).with(nil, nil).and_return(result)
    Flapjack::Gateways::API::EntityPresenter.should_receive(:new).
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
    Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
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
    Flapjack::Gateways::API::EntityPresenter.should_receive(:new).
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
    Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
      with(entity_check).and_return(entity_check_presenter)
    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)
    Flapjack::Data::EntityCheck.should_receive(:for_entity).
      with(entity, check, :redis => redis).and_return(entity_check)

    get "/downtime/#{entity_name_esc}/#{check}"
    last_response.should be_ok
    last_response.body.should == result_json
  end

  it "creates a test notification event for check on an entity" do

    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)
    entity.should_receive(:name).and_return(entity_name)
    Flapjack::Data::EntityCheck.should_receive(:for_entity).
      with(entity, 'foo', :redis => redis).and_return(entity_check)
    entity_check.should_receive(:test_notifications)

    post "/test_notifications/#{entity_name_esc}/foo"
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
    last_response.status.should == 200
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
    last_response.status.should == 200
  end

  it "creates contacts from a submitted list" do
    contacts = {'contacts' =>
      [{"id" => "0362",
        "first_name" => "John",
        "last_name" => "Smith",
        "email" => "johns@example.dom",
        "media" => {"email"  => "johns@example.dom",
                    "jabber" => "johns@conference.localhost"}},
       {"id" => "0363",
        "first_name" => "Jane",
        "last_name" => "Jones",
        "email" => "jane@example.dom",
        "media" => {"email" => "jane@example.dom"}}
      ]
    }

    Flapjack::Data::Contact.should_receive(:delete_all)
    Flapjack::Data::Contact.should_receive(:add).twice

    post "/contacts", contacts.to_json, {'CONTENT_TYPE' => 'application/json'}
    last_response.status.should == 200
  end

  it "does not create contacts if the data is improperly formatted" do
    Flapjack::Data::Contact.should_not_receive(:delete_all)
    Flapjack::Data::Contact.should_not_receive(:add)

    post "/contacts", {'contacts' => ["Hello", "again"]}.to_json,
      {'CONTENT_TYPE' => 'application/json'}
    last_response.status.should == 403
  end

  it "does not create contacts if they don't contain an id" do
    contacts = {'contacts' =>
      [{"id" => "0362",
        "first_name" => "John",
        "last_name" => "Smith",
        "email" => "johns@example.dom",
        "media" => {"email"  => "johns@example.dom",
                    "jabber" => "johns@conference.localhost"}},
       {"first_name" => "Jane",
        "last_name" => "Jones",
        "email" => "jane@example.dom",
        "media" => {"email" => "jane@example.dom"}}
      ]
    }

    Flapjack::Data::Contact.should_receive(:delete_all)
    Flapjack::Data::Contact.should_receive(:add)

    post "/contacts", contacts.to_json, {'CONTENT_TYPE' => 'application/json'}
    last_response.status.should == 200
  end

  it "returns a list of medias for a contact" do
    result_json = contact_media_list.to_json
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact_id, :redis => redis).and_return(contact)
    contact.should_receive(:media_list).and_return(contact_media_list)

    get "/contacts/#{contact_id}/media"
    last_response.should be_ok
    last_response.body.should be_json_eql(result_json)
  end

end
