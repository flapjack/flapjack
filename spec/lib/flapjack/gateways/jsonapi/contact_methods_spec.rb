require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::ContactMethods', :sinatra => true, :logger => true do

  include_context "jsonapi"

  # let(:json_data)       { {'valid' => 'json'} }

  # let(:media) {
  #   {'email' => 'ada@example.com',
  #    'sms'   => '04123456789'
  #   }
  # }

  # let(:media_intervals) {
  #   {'email' => 500,
  #    'sms'   => 300
  #   }
  # }

  # let(:media_rollup_thresholds) {
  #   {'email' => 5}
  # }

  # let(:notification_rule) {
  #   double(Flapjack::Data::NotificationRule, :id => '1', :contact_id => '21')
  # }

  # let(:notification_rule_data) {
  #   {"contact_id"         => "21",
  #    "tags"               => ["database","physical"],
  #    "entities"           => ["foo-app-01.example.com"],
  #    "time_restrictions"  => nil,
  #    "unknown_media"      => ["jabber"],
  #    "warning_media"      => ["email"],
  #    "critical_media"     => ["sms", "email"],
  #    "unknown_blackhole"  => false,
  #    "warning_blackhole"  => false,
  #    "critical_blackhole" => false
  #   }
  # }

  # let(:critical_state) { double(Flapjack::Data::NotificationRuleState) }
  # let(:warning_state)  { double(Flapjack::Data::NotificationRuleState) }
  # let(:unknown_state)  { double(Flapjack::Data::NotificationRuleState) }

  it "creates a contact" # do
    # contact_data = {
    #   "id"         => "0362",
    #   "first_name" => "John",
    #   "last_name"  => "Smith",
    #   "email"      => "johns@example.dom",
    #   "media"      => {
    #     "email"  => "johns@example.dom",
    #     "jabber" => "johns@conference.localhost"
    #   }
    # }

    # expect(Flapjack::Data::Semaphore).to receive(:new).
    #   with("contact_mass_update", {:redis => redis, :expiry => 30}).and_return(semaphore)
    # expect(Flapjack::Data::Contact).to receive(:exists_with_id?).
    #   with("0362", {:redis => redis}).and_return(false)
    # expect(Flapjack::Data::Contact).to receive(:add).
    #   with(contact_data, {:redis => redis}).and_return(contact)
    # expect(semaphore).to receive(:release).and_return(true)

    # post "/contacts", {:contacts => [contact_data]}.to_json, jsonapi_post_env
    # expect(last_response.status).to eq(201)
    # expect(last_response.body).to eq(["0362"].to_json)
  # end

  it "does not create a contact if the data is improperly formatted" # do
    # expect(Flapjack::Data::Contact).not_to receive(:add)

    # post "/contacts", {'sausage' => 'good'}.to_json, jsonapi_post_env
    # expect(last_response.status).to eq(422)
  # end

  it "returns all the contacts" do
    expect(Flapjack::Data::Contact).to receive(:associated_ids_for_entities).
      with([contact.id]).and_return({})
    expect(Flapjack::Data::Contact).to receive(:associated_ids_for_media).
      with([contact.id]).and_return({})
    expect(Flapjack::Data::Contact).to receive(:associated_ids_for_pagerduty_credentials).
      with([contact.id]).and_return({})
    expect(Flapjack::Data::Contact).to receive(:associated_ids_for_notification_rules).
      with([contact.id]).and_return({})
    expect(contact).to receive(:as_json).and_return(contact_core)
    expect(Flapjack::Data::Contact).to receive(:all).and_return([contact])

    get '/contacts'
    expect(last_response).to be_ok
    expect(last_response.body).to eq({:contacts => [contact_core]}.to_json)
  end

  it "returns the core information of a specified contact" do
    expect(Flapjack::Data::Contact).to receive(:associated_ids_for_entities).
      with([contact.id]).and_return({})
    expect(Flapjack::Data::Contact).to receive(:associated_ids_for_media).
      with([contact.id]).and_return({})
    expect(Flapjack::Data::Contact).to receive(:associated_ids_for_pagerduty_credentials).
      with([contact.id]).and_return({})
    expect(Flapjack::Data::Contact).to receive(:associated_ids_for_notification_rules).
      with([contact.id]).and_return({})
    expect(contact).to receive(:as_json).and_return(contact_core)
    expect(Flapjack::Data::Contact).to receive(:find_by_ids!).
      with([contact.id]).and_return([contact])

    get "/contacts/#{contact.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq({:contacts => [contact_core]}.to_json)
  end

  it "does not return information for a contact that does not exist" do
    expect(Flapjack::Data::Contact).to receive(:find_by_ids!).
      with([contact.id]).and_raise(Sandstorm::Errors::RecordsNotFound.new(Flapjack::Data::Contact, [contact.id]))

    get "/contacts/#{contact.id}"
    expect(last_response.status).to eq(404)
  end

  it "updates a contact" do
    expect(Flapjack::Data::Contact).to receive(:find_by_ids).
      with([contact.id]).and_return([contact])

    expect(contact).to receive(:first_name=).with('Elias')
    expect(contact).to receive(:save).and_return(true)

    expect(Flapjack::Data::Contact).to receive(:lock).and_yield

    patch "/contacts/#{contact.id}",
      [{:op => 'replace', :path => '/contacts/0/first_name', :value => 'Elias'}].to_json,
      jsonapi_patch_env
    expect(last_response.status).to eq(204)
  end

  it "deletes a contact" do
    expect(Flapjack::Data::Contact).to receive(:find_by_ids).
      with([contact.id]).and_return([contact])
    expect(contact).to receive(:destroy)

    expect(Flapjack::Data::Contact).to receive(:lock).and_yield

    delete "/contacts/#{contact.id}"
    expect(last_response.status).to eq(204)
  end

end
