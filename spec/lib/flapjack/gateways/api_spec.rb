require 'spec_helper'
require 'flapjack/gateways/api'

describe 'Flapjack::Gateways::API', :sinatra => true, :logger => true, :json => true do

  def app
    Flapjack::Gateways::API
  end

  let(:entity)          { mock(Flapjack::Data::Entity) }
  let(:entity_check)    { mock(Flapjack::Data::EntityCheck) }

  let(:entity_name)     { 'www.example.net'}
  let(:entity_name_esc) { URI.escape(entity_name) }
  let(:check)           { 'ping' }

  let(:contact)         { mock(Flapjack::Data::Contact, :id => '21') }
  let(:contact_core)    {
    {'id'         => contact.id,
     'first_name' => "Ada",
     'last_name'  => "Lovelace",
     'email'      => "ada@example.com",
     'tags'       => ["legend", "first computer programmer"]
    }
  }

  let(:media) {
    {'email' => 'ada@example.com',
     'sms'   => '04123456789'
    }
  }

  let(:media_intervals) {
    {'email' => 500,
     'sms'   => 300
    }
  }

  let(:entity_presenter)       { mock(Flapjack::Gateways::API::EntityPresenter) }
  let(:entity_check_presenter) { mock(Flapjack::Gateways::API::EntityCheckPresenter) }

  let(:redis)           { mock(::Redis) }

  let(:notification_rule) {
    mock(Flapjack::Data::NotificationRule, :id => '1', :contact_id => '21')
  }

  let(:notification_rule_data) {
    {"contact_id"         => "21",
     "entity_tags"        => ["database","physical"],
     "entities"           => ["foo-app-01.example.com"],
     "time_restrictions"  => nil,
     "warning_media"      => ["email"],
     "critical_media"     => ["sms", "email"],
     "warning_blackhole"  => false,
     "critical_blackhole" => false
    }
  }

  before(:all) do
    Flapjack::Gateways::API.class_eval {
      set :raise_errors, true
    }
    Flapjack::Gateways::API.instance_variable_get('@middleware').delete_if {|m|
      m[0] == Rack::FiberPool
    }
  end

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

    Flapjack::Data::Contact.should_receive(:all).with(:redis => redis).and_return([])
    Flapjack::Data::Contact.should_receive(:add).twice

    post "/contacts", contacts.to_json, {'CONTENT_TYPE' => 'application/json'}
    last_response.status.should == 200
  end

  it "does not create contacts if the data is improperly formatted" do
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

    Flapjack::Data::Contact.should_receive(:all).with(:redis => redis).and_return([])
    Flapjack::Data::Contact.should_receive(:add)

    post "/contacts", contacts.to_json, {'CONTENT_TYPE' => 'application/json'}
    last_response.status.should == 200
  end

  it "updates a contact if it is already present" do
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

    existing = mock(Flapjack::Data::Contact)
    existing.should_receive(:id).and_return("0363")
    existing.should_receive(:update).with(contacts['contacts'][1])

    Flapjack::Data::Contact.should_receive(:all).with(:redis => redis).and_return([existing])
    Flapjack::Data::Contact.should_receive(:add).with(contacts['contacts'][0], :redis => redis)

    post "/contacts", contacts.to_json, {'CONTENT_TYPE' => 'application/json'}
    last_response.status.should == 200
  end

  it "deletes a contact not found in a bulk update list" do
    contacts = {'contacts' =>
      [{"id" => "0363",
        "first_name" => "Jane",
        "last_name" => "Jones",
        "email" => "jane@example.dom",
        "media" => {"email" => "jane@example.dom"}}
      ]
    }

    existing = mock(Flapjack::Data::Contact)
    existing.should_receive(:id).twice.and_return("0362")
    existing.should_receive(:delete!)

    Flapjack::Data::Contact.should_receive(:all).with(:redis => redis).and_return([existing])
    Flapjack::Data::Contact.should_receive(:add).with(contacts['contacts'][0], :redis => redis)

    post "/contacts", contacts.to_json, {'CONTENT_TYPE' => 'application/json'}
    last_response.status.should == 200
  end

  it "returns all the contacts" do
    contact.should_receive(:to_json).and_return(contact_core.to_json)
    Flapjack::Data::Contact.should_receive(:all).with(:redis => redis).
      and_return([contact])

    get '/contacts'
    last_response.should be_ok
    last_response.body.should be_json_eql([contact_core].to_json)
  end

  it "returns the core information of a specified contact" do
    contact.should_receive(:to_json).and_return(contact_core.to_json)
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(contact)

    get "/contacts/#{contact.id}"
    last_response.should be_ok
    last_response.body.should be_json_eql(contact_core.to_json)
  end

  it "does not return information for a contact that does not exist" do
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(nil)

    get "/contacts/#{contact.id}"
    last_response.should be_not_found
  end

  it "lists a contact's notification rules" do
    notification_rule_2 = mock(Flapjack::Data::NotificationRule, :id => '2', :contact_id => '21')
    notification_rule.should_receive(:to_json).and_return('"rule_1"')
    notification_rule_2.should_receive(:to_json).and_return('"rule_2"')
    notification_rules = [ notification_rule, notification_rule_2 ]

    contact.should_receive(:notification_rules).and_return(notification_rules)
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(contact)

    get "/contacts/#{contact.id}/notification_rules"
    last_response.should be_ok
    last_response.body.should be_json_eql( '["rule_1", "rule_2"]' )
  end

  it "does not list notification rules for a contact that does not exist" do
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(nil)

    get "/contacts/#{contact.id}/notification_rules"
    last_response.should be_not_found
  end

  it "returns a specified notification rule" do
    notification_rule.should_receive(:to_json).and_return('"rule_1"')
    Flapjack::Data::NotificationRule.should_receive(:find_by_id).
      with(notification_rule.id, :redis => redis).and_return(notification_rule)

    get "/notification_rules/#{notification_rule.id}"
    last_response.should be_ok
    last_response.body.should be_json_eql('"rule_1"')
  end

  it "does not return a notification rule that does not exist" do
    Flapjack::Data::NotificationRule.should_receive(:find_by_id).
      with(notification_rule.id, :redis => redis).and_return(nil)

    get "/notification_rules/#{notification_rule.id}"
    last_response.should be_not_found
  end

  # POST /notification_rules
  it "creates a new notification rule" do
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(contact)
    notification_rule.should_receive(:to_json).and_return('"rule_1"')

    # symbolize the keys
    notification_rule_data_sym = notification_rule_data.inject({}){|memo,(k,v)|
      memo[k.to_sym] = v; memo
    }
    notification_rule_data_sym.delete(:contact_id)

    contact.should_receive(:add_notification_rule).
      with(notification_rule_data_sym).and_return(notification_rule)

    post "/notification_rules", notification_rule_data.to_json,
      {'CONTENT_TYPE' => 'application/json'}
    last_response.should be_ok
    last_response.body.should be_json_eql('"rule_1"')
  end

  it "does not create a notification_rule for a contact that's not present" do
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(nil)

    post "/notification_rules", notification_rule_data.to_json,
      {'CONTENT_TYPE' => 'application/json'}
    last_response.should be_not_found
  end

  it "does not create a notification_rule if a rule id is provided" do
    contact.should_not_receive(:add_notification_rule)
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(contact)

    post "/notification_rules", notification_rule_data.merge(:id => 1).to_json,
      {'CONTENT_TYPE' => 'application/json'}
    last_response.status.should == 403
  end

  # PUT /notification_rules/RULE_ID
  it "updates a notification rule" do
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(contact)
    notification_rule.should_receive(:to_json).and_return('"rule_1"')
    Flapjack::Data::NotificationRule.should_receive(:find_by_id).
      with(notification_rule.id, :redis => redis).and_return(notification_rule)

    # symbolize the keys
    notification_rule_data_sym = notification_rule_data.inject({}){|memo,(k,v)|
      memo[k.to_sym] = v; memo
    }
    notification_rule_data_sym.delete(:contact_id)

    notification_rule.should_receive(:update).with(notification_rule_data_sym)

    put "/notification_rules/#{notification_rule.id}", notification_rule_data.to_json,
      {'CONTENT_TYPE' => 'application/json'}
    last_response.should be_ok
    last_response.body.should be_json_eql('"rule_1"')
  end

  it "does not update a notification rule that's not present" do
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(contact)
    Flapjack::Data::NotificationRule.should_receive(:find_by_id).
      with(notification_rule.id, :redis => redis).and_return(nil)

    put "/notification_rules/#{notification_rule.id}", notification_rule_data
    last_response.should be_not_found
  end

  it "does not update a notification_rule for a contact that's not present" do
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(nil)

    put "/notification_rules/#{notification_rule.id}", notification_rule_data.to_json,
      {'CONTENT_TYPE' => 'application/json'}
    last_response.should be_not_found
  end

  # DELETE /notification_rules/RULE_ID
  it "deletes a notification rule" do
    notification_rule.should_receive(:contact_id).and_return(contact.id)
    Flapjack::Data::NotificationRule.should_receive(:find_by_id).
      with(notification_rule.id, :redis => redis).and_return(notification_rule)
    contact.should_receive(:delete_notification_rule).with(notification_rule)
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(contact)

    delete "/notification_rules/#{notification_rule.id}"
    last_response.status.should == 204
  end

  it "does not delete a notification rule that's not present" do
    Flapjack::Data::NotificationRule.should_receive(:find_by_id).
      with(notification_rule.id, :redis => redis).and_return(nil)

    delete "/notification_rules/#{notification_rule.id}"
    last_response.should be_not_found
  end

  it "does not delete a notification rule if the contact is not present" do
    notification_rule.should_receive(:contact_id).and_return(contact.id)
    Flapjack::Data::NotificationRule.should_receive(:find_by_id).
      with(notification_rule.id, :redis => redis).and_return(notification_rule)
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(nil)

    delete "/notification_rules/#{notification_rule.id}"
    last_response.should be_not_found
  end

  # GET /contacts/CONTACT_ID/media
  it "returns the media of a contact" do
    contact.should_receive(:media).and_return(media)
    contact.should_receive(:media_intervals).and_return(media_intervals)
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(contact)
    result = Hash[ *(media.keys.collect {|m|
      [m, {'address'  => media[m],
           'interval' => media_intervals[m] }]
      }).flatten(1)].to_json

    get "/contacts/#{contact.id}/media"
    last_response.should be_ok
    last_response.body.should be_json_eql(result)
  end

  it "does not return the media of a contact if the contact is not present" do
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(nil)

    get "/contacts/#{contact.id}/media"
    last_response.should be_not_found
  end

  # GET /contacts/CONTACT_ID/media/MEDIA
  it "returns the specified media of a contact" do
    contact.should_receive(:media).twice.and_return(media)
    contact.should_receive(:media_intervals).and_return(media_intervals)
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(contact)

    result = {'address' => media['sms'], 'interval' => media_intervals['sms']}

    get "/contacts/#{contact.id}/media/sms"
    last_response.should be_ok
    last_response.body.should be_json_eql(result.to_json)
  end

  it "does not return the media of a contact if the contact is not present" do
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(nil)

    get "/contacts/#{contact.id}/media/sms"
    last_response.should be_not_found
  end

  it "does not return the media of a contact if the media is not present" do
    contact.should_receive(:media).and_return(media)
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(contact)

    get "/contacts/#{contact.id}/media/telepathy"
    last_response.should be_not_found
  end

  # PUT, DELETE /contacts/CONTACT_ID/media/MEDIA
  it "creates/updates a media of a contact" do
    # as far as API is concerned these are the same -- contact.rb spec test
    # may distinguish between them
    alt_media = media.merge('sms' => '04987654321')
    alt_media_intervals = media_intervals.merge('sms' => '200')

    contact.should_receive(:set_address_for_media).with('sms', '04987654321')
    contact.should_receive(:set_interval_for_media).with('sms', '200')
    contact.should_receive(:media).and_return(alt_media)
    contact.should_receive(:media_intervals).and_return(alt_media_intervals)
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(contact)

    result = {'address' => alt_media['sms'], 'interval' => alt_media_intervals['sms']}

    put "/contacts/#{contact.id}/media/sms", {:address => '04987654321', :interval => '200'}
    last_response.should be_ok
    last_response.body.should be_json_eql(result.to_json)
  end

  it "does not create a media of a contact that's not present" do
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(nil)

    put "/contacts/#{contact.id}/media/sms", {:address => '04987654321', :interval => '200'}
    last_response.should be_not_found
  end

  it "does not create a media of a contact if no address is provided" do
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(contact)

    put "/contacts/#{contact.id}/media/sms", {:interval => '200'}
    last_response.should be_forbidden
  end

  it "does not create a media of a contact if no interval is provided" do
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(contact)

    put "/contacts/#{contact.id}/media/sms", {:address => '04987654321'}
    last_response.should be_forbidden
  end

  it "deletes a media of a contact" do
    contact.should_receive(:remove_media).with('sms')
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(contact)

    delete "/contacts/#{contact.id}/media/sms"
    last_response.status.should == 204
  end

  it "does not delete a media of a contact that's not present" do
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(nil)

    delete "/contacts/#{contact.id}/media/sms"
    last_response.should be_not_found
  end

  # GET /contacts/CONTACT_ID/timezone
  it "returns the timezone of a contact" do
    contact.should_receive(:timezone).and_return(::ActiveSupport::TimeZone.new('Australia/Sydney'))
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(contact)

    get "/contacts/#{contact.id}/timezone"
    last_response.should be_ok
    last_response.body.should be_json_eql('"Australia/Sydney"')
  end

  it "doesn't get the timezone of a contact that doesn't exist" do
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(nil)

    get "/contacts/#{contact.id}/timezone"
    last_response.should be_not_found
  end

  # PUT /contacts/CONTACT_ID/timezone
  it "sets the timezone of a contact" do
    contact.should_receive(:timezone=).with('Australia/Perth')
    contact.should_receive(:timezone).and_return(ActiveSupport::TimeZone.new('Australia/Perth'))
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(contact)

    put "/contacts/#{contact.id}/timezone", {:timezone => 'Australia/Perth'}
    last_response.should be_ok
  end

  it "doesn't set the timezone of a contact who can't be found" do
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(nil)

    put "/contacts/#{contact.id}/timezone", {:timezone => 'Australia/Perth'}
    last_response.should be_not_found
  end

  # DELETE /contacts/CONTACT_ID/timezone
  it "deletes the timezone of a contact" do
    contact.should_receive(:timezone=).with(nil)
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(contact)

    delete "/contacts/#{contact.id}/timezone"
    last_response.status.should == 204
  end

  it "does not delete the timezone of a contact that's not present" do
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(nil)

    delete "/contacts/#{contact.id}/timezone"
    last_response.should be_not_found
  end



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
    last_response.should be_not_found
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
    last_response.should be_not_found
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
    last_response.should be_not_found
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
    last_response.should be_not_found
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
    last_response.should be_not_found
  end


  it "sets a single tag on a contact and returns current tags" do
    contact.should_receive(:add_tags).with('web')
    contact.should_receive(:tags).and_return(['web'])
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(contact)

    post "contacts/#{contact.id}/tags", :tag => 'web'
    last_response.should be_ok
    last_response.body.should be_json_eql( ['web'].to_json )
  end

  it "does not set a single tag on a contact that's not found" do
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(nil)

    post "contacts/#{contact.id}/tags", :tag => 'web'
    last_response.should be_not_found
  end

  it "sets multiple tags on a contact and returns current tags" do
    contact.should_receive(:add_tags).with('web', 'app')
    contact.should_receive(:tags).and_return(['web', 'app'])
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(contact)

    post "contacts/#{contact.id}/tags", :tag => ['web', 'app']
    last_response.should be_ok
    last_response.body.should be_json_eql( ['web', 'app'].to_json )
  end

  it "does not set multiple tags on a contact that's not found" do
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(nil)

    post "contacts/#{contact.id}/tags", :tag => ['web', 'app']
    last_response.should be_not_found
  end

  it "removes a single tag from a contact" do
    contact.should_receive(:delete_tags).with('web')
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(contact)

    delete "contacts/#{contact.id}/tags", :tag => 'web'
    last_response.status.should == 204
  end

  it "does not remove a single tag from a contact that's not found" do
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(nil)

    delete "contacts/#{contact.id}/tags", :tag => 'web'
    last_response.should be_not_found
  end

  it "removes multiple tags from a contact" do
    contact.should_receive(:delete_tags).with('web', 'app')
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(contact)

    delete "contacts/#{contact.id}/tags", :tag => ['web', 'app']
    last_response.status.should == 204
  end

  it "does not remove multiple tags from a contact that's not found" do
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(nil)

    delete "contacts/#{contact.id}/tags", :tag => ['web', 'app']
    last_response.should be_not_found
  end

  it "gets all tags on a contact" do
    contact.should_receive(:tags).and_return(['web', 'app'])
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(contact)

    get "contacts/#{contact.id}/tags"
    last_response.should be_ok
    last_response.body.should be_json_eql( ['web', 'app'].to_json )
  end

  it "does not get all tags on a contact that's not found" do
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(nil)

    get "contacts/#{contact.id}/tags"
    last_response.should be_not_found
  end

  it "gets all entity tags for a contact" do
    entity_1 = mock(Flapjack::Data::Entity)
    entity_1.should_receive(:name).and_return('entity_1')
    entity_2 = mock(Flapjack::Data::Entity)
    entity_2.should_receive(:name).and_return('entity_2')
    tag_data = [{:entity => entity_1, :tags => ['web']},
                {:entity => entity_2, :tags => ['app']}]
    contact.should_receive(:entities).with(:tags => true).
      and_return(tag_data)

    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(contact)

    get "contacts/#{contact.id}/entity_tags"
    last_response.should be_ok
    tag_response = {'entity_1' => ['web'],
                    'entity_2' => ['app']}
    last_response.body.should be_json_eql( tag_response.to_json )
  end

  it "does not get all entity tags for a contact that's not found" do
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(nil)

    get "contacts/#{contact.id}/entity_tags"
    last_response.should be_not_found
  end

  it "adds tags to multiple entities for a contact" do
    entity_1 = mock(Flapjack::Data::Entity)
    entity_1.should_receive(:name).twice.and_return('entity_1')
    entity_1.should_receive(:add_tags).with('web')
    entity_2 = mock(Flapjack::Data::Entity)
    entity_2.should_receive(:name).twice.and_return('entity_2')
    entity_2.should_receive(:add_tags).with('app')

    entities = [{:entity => entity_1}, {:entity => entity_2}]
    contact.should_receive(:entities).and_return(entities)
    tag_data = [{:entity => entity_1, :tags => ['web']},
                {:entity => entity_2, :tags => ['app']}]
    contact.should_receive(:entities).with(:tags => true).and_return(tag_data)

    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(contact)

    post "contacts/#{contact.id}/entity_tags",
      :entity => {'entity_1' => ['web'], 'entity_2' => ['app']}
    last_response.should be_ok
    tag_response = {'entity_1' => ['web'],
                    'entity_2' => ['app']}
    last_response.body.should be_json_eql( tag_response.to_json )
  end

  it "does not add tags to multiple entities for a contact that's not found" do
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(nil)

    post "contacts/#{contact.id}/entity_tags",
      :entity => {'entity_1' => ['web'], 'entity_2' => ['app']}
    last_response.should be_not_found
  end

  it "deletes tags from multiple entities for a contact" do
    entity_1 = mock(Flapjack::Data::Entity)
    entity_1.should_receive(:name).and_return('entity_1')
    entity_1.should_receive(:delete_tags).with('web')
    entity_2 = mock(Flapjack::Data::Entity)
    entity_2.should_receive(:name).and_return('entity_2')
    entity_2.should_receive(:delete_tags).with('app')

    entities = [{:entity => entity_1}, {:entity => entity_2}]
    contact.should_receive(:entities).and_return(entities)

    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(contact)

    delete "contacts/#{contact.id}/entity_tags",
      :entity => {'entity_1' => ['web'], 'entity_2' => ['app']}
    last_response.status.should == 204
  end

  it "does not delete tags from multiple entities for a contact that's not found" do
    Flapjack::Data::Contact.should_receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(nil)

    delete "contacts/#{contact.id}/entity_tags",
      :entity => {'entity_1' => ['web'], 'entity_2' => ['app']}
    last_response.should be_not_found
  end

end
