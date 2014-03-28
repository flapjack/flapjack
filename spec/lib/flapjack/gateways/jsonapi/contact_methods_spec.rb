require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::ContactMethods', :sinatra => true, :logger => true do

  def app
    Flapjack::Gateways::JSONAPI
  end

  let(:contact)      { double(Flapjack::Data::Contact, :id => '21') }
  let(:contact_core) {
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

  let(:media_rollup_thresholds) {
    {'email' => 5}
  }

  let(:redis)           { double(::Redis) }

  let(:notification_rule) {
    double(Flapjack::Data::NotificationRule, :id => '1', :contact_id => '21')
  }

  let(:notification_rule_data) {
    {"contact_id"         => "21",
     "tags"               => ["database","physical"],
     "regex_tags"         => ["^data.*$","^(physical|bare_metal)$"],
     "regex_entities"     => ["^foo-\S{3}-\d{2}.example.com$"],
     "time_restrictions"  => nil,
     "unknown_media"      => ["jabber"],
     "warning_media"      => ["email"],
     "critical_media"     => ["sms", "email"],
     "unknown_blackhole"  => false,
     "warning_blackhole"  => false,
     "critical_blackhole" => false
    }
  }

  let(:semaphore) {
    double(Flapjack::Data::Semaphore, :resource => 'folly',
           :key => 'semaphores:folly', :expiry => 30, :token => 'spatulas-R-us')
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

  it "returns all the contacts" do
    expect(Flapjack::Data::Contact).to receive(:entities_jsonapi).
      with([contact.id], :redis => redis).and_return([[], {}])
    expect(contact).to receive(:media).and_return({})
    expect(contact).to receive(:linked_entity_ids=).with(nil)
    expect(contact).to receive(:linked_media_ids=).with(nil)
    expect(contact).to receive(:to_jsonapi).and_return(contact_core.to_json)
    expect(Flapjack::Data::Contact).to receive(:all).with(:redis => redis).
      and_return([contact])

    aget '/contacts'
    expect(last_response).to be_ok
    expect(last_response.body).to eq({:contacts => [contact_core], :linked => {'entities' => [], 'media' => []}}.to_json)
  end

  it "returns the core information of a specified contact" do
    #expect(contact).to receive(:entities).and_return([])
    expect(Flapjack::Data::Contact).to receive(:entities_jsonapi).
      with([contact.id], :redis => redis).and_return([[], {}])
    expect(contact).to receive(:media).and_return({})
    expect(contact).to receive(:linked_entity_ids=).with(nil)
    expect(contact).to receive(:linked_media_ids=).with(nil)
    expect(contact).to receive(:to_jsonapi).and_return(contact_core.to_json)
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(contact)

    aget "/contacts/#{contact.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq({:contacts => [contact_core], :linked => {'entities' => [], 'media' => []}}.to_json)
  end

  it "does not return information for a contact that does not exist" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(nil)

    aget "/contacts/#{contact.id}"
    expect(last_response.status).to eq(404)
  end

  it "creates a contact with supplied ID" do
    #FIXME: I think media should be removed from this interface
    contact_data = {
      "id"         => "0362",
      "first_name" => "John",
      "last_name"  => "Smith",
      "email"      => "johns@example.dom",
      "media"      => {
        "email"  => "johns@example.dom",
        "jabber" => "johns@conference.localhost"
      }
    }

    expect(Flapjack::Data::Semaphore).to receive(:new).
      with("contact_mass_update", {:redis => redis, :expiry => 30}).and_return(semaphore)
    expect(Flapjack::Data::Contact).to receive(:exists_with_id?).
      with("0362", {:redis => redis}).and_return(false)
    expect(Flapjack::Data::Contact).to receive(:add).
      with(contact_data, {:redis => redis}).and_return(contact)
    expect(semaphore).to receive(:release).and_return(true)

    apost "/contacts", { :contacts => [contact_data]}.to_json,
      {'CONTENT_TYPE' => Flapjack::Gateways::JSONAPI::JSONAPI_MEDIA_TYPE}

    expect(last_response.status).to eq(200)
    expect(last_response.body).to eq(["0362"].to_json)
  end

  it "updates a contact" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(contact)
    expect(contact).to receive(:update)
    expect(contact).to receive(:to_jsonapi).and_return('{"sausage": "good"}')

    aput "/contacts/21", {:contacts => [{'sausage' => 'good'}]}.to_json,
      {'CONTENT_TYPE' => Flapjack::Gateways::JSONAPI::JSONAPI_MEDIA_TYPE}
    expect(last_response.status).to eq(200)
  end

  it "deletes a contact" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(contact)
    expect(Flapjack::Data::Semaphore).to receive(:new).and_return(semaphore)
    expect(semaphore).to receive(:release)
    expect(contact).to receive(:delete!)

    adelete "/contacts/21"
    expect(last_response.status).to eq(204)
  end

  it "does not create a contact if the data is improperly formatted" do
    expect(Flapjack::Data::Contact).not_to receive(:add)

    apost "/contacts", {'sausage' => 'good'}.to_json,
      {'CONTENT_TYPE' => Flapjack::Gateways::JSONAPI::JSONAPI_MEDIA_TYPE}
    expect(last_response.status).to eq(422)
  end

  it "does not update a contact if id exists in sent entity" do
    contact_data = {'id' => '21'}
    expect(Flapjack::Data::Contact).not_to receive(:find_by_id)
    expect(Flapjack::Data::Contact).not_to receive(:update)

    aput "/contacts/21", contact_data.to_json,
      {'CONTENT_TYPE' => Flapjack::Gateways::JSONAPI::JSONAPI_MEDIA_TYPE}
    expect(last_response.status).to eq(422)
  end

  it "returns a specified notification rule" do
    expect(notification_rule).to receive(:to_json).and_return('"rule_1"')
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_id).
      with(notification_rule.id, {:redis => redis, :logger => @logger}).and_return(notification_rule)

    aget "/notification_rules/#{notification_rule.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq('{"notification_rules":["rule_1"]}')
  end

  it "does not return a notification rule that does not exist" do
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_id).
      with(notification_rule.id, {:redis => redis, :logger => @logger}).and_return(nil)

    aget "/notification_rules/#{notification_rule.id}"
    expect(last_response.status).to eq(404)
  end

  # POST /notification_rules
  it "creates a new notification rule" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(contact)
    expect(notification_rule).to receive(:respond_to?).with(:critical_media).and_return(true)
    expect(notification_rule).to receive(:to_json).and_return('"rule_1"')

    # symbolize the keys
    notification_rule_data_sym = notification_rule_data.inject({}){|memo,(k,v)|
      memo[k.to_sym] = v; memo
    }
    notification_rule_data_sym.delete(:contact_id)

    expect(contact).to receive(:add_notification_rule).
      with(notification_rule_data_sym, :logger => @logger).and_return(notification_rule)

    apost "/notification_rules", {"notification_rules" => [notification_rule_data]}.to_json,
      {'CONTENT_TYPE' => Flapjack::Gateways::JSONAPI::JSONAPI_MEDIA_TYPE}
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq('{"notification_rules":["rule_1"]}')
  end

  it "does not create a notification_rule for a contact that's not present" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(nil)

    apost "/notification_rules", {"notification_rules" => [notification_rule_data]}.to_json,
      {'CONTENT_TYPE' => Flapjack::Gateways::JSONAPI::JSONAPI_MEDIA_TYPE}
    expect(last_response.status).to eq(404)
  end

  # PUT /notification_rules/RULE_ID
  it "updates a notification rule" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(contact)
    expect(notification_rule).to receive(:to_json).and_return('"rule_1"')
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_id).
      with(notification_rule.id, {:redis => redis, :logger => @logger}).and_return(notification_rule)

    # symbolize the keys
    notification_rule_data_sym = notification_rule_data.inject({}){|memo,(k,v)|
      memo[k.to_sym] = v; memo
    }
    notification_rule_data_sym.delete(:contact_id)

    expect(notification_rule).to receive(:update).with(notification_rule_data_sym, :logger => @logger).and_return(nil)

    aput "/notification_rules/#{notification_rule.id}", {"notification_rules" => [notification_rule_data]}.to_json,
      {'CONTENT_TYPE' => Flapjack::Gateways::JSONAPI::JSONAPI_MEDIA_TYPE}
    expect(last_response).to be_ok
    expect(last_response.body).to eq('{"notification_rules":["rule_1"]}')
  end

  it "does not update a notification rule that's not present" do
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_id).
      with(notification_rule.id, {:redis => redis, :logger => @logger}).and_return(nil)

    aput "/notification_rules/#{notification_rule.id}", {"notification_rules" => [notification_rule_data]}.to_json,
      {'CONTENT_TYPE' => Flapjack::Gateways::JSONAPI::JSONAPI_MEDIA_TYPE}
    expect(last_response.status).to eq(404)
  end

  it "does not update a notification_rule for a contact that's not present" do
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_id).
      with(notification_rule.id, {:redis => redis, :logger => @logger}).and_return(notification_rule)
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(nil)

    aput "/notification_rules/#{notification_rule.id}", {"notification_rules" => [notification_rule_data]}.to_json,
      {'CONTENT_TYPE' => Flapjack::Gateways::JSONAPI::JSONAPI_MEDIA_TYPE}
    expect(last_response.status).to eq(404)
  end

  # DELETE /notification_rules/RULE_ID
  it "deletes a notification rule" do
    expect(notification_rule).to receive(:contact_id).and_return(contact.id)
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_id).
      with(notification_rule.id, {:redis => redis, :logger => @logger}).and_return(notification_rule)
    expect(contact).to receive(:delete_notification_rule).with(notification_rule)
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(contact)

    adelete "/notification_rules/#{notification_rule.id}"
    expect(last_response.status).to eq(204)
  end

  it "does not delete a notification rule that's not present" do
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_id).
      with(notification_rule.id, {:redis => redis, :logger => @logger}).and_return(nil)

    adelete "/notification_rules/#{notification_rule.id}"
    expect(last_response.status).to eq(404)
  end

  it "does not delete a notification rule if the contact is not present" do
    expect(notification_rule).to receive(:contact_id).and_return(contact.id)
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_id).
      with(notification_rule.id, {:redis => redis, :logger => @logger}).and_return(notification_rule)
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(nil)

    adelete "/notification_rules/#{notification_rule.id}"
    expect(last_response.status).to eq(404)
  end

  it "returns the media of a contact"

  it "returns the specified media of a contact"

  it "does not return the media of a contact if the media is not present"

  it "creates/updates a media of a contact"

  it "updates a contact's pagerduty media credentials"

  it "does not create a media of a contact that's not present"

  it "does not create a media of a contact if no address is provided"

  it "creates a media of a contact even if no interval is provided"

  it "deletes a media of a contact"

  it "does not delete a media of a contact that's not present"

end
