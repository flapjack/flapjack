require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::NotificationRuleMethods', :sinatra => true, :logger => true do

  include_context "jsonapi"

  let (:notification_rule) {
    double(Flapjack::Data::NotificationRule, :id => '1')
  }

  let(:notification_rule_data) {
    {"tags"               => ["database","physical"],
     "regex_tags"         => ["^data.*$","^(physical|bare_metal)$"],
     "regex_entities"     => ["^foo-\S{3}-\d{2}.example.com$"],
     "time_restrictions"  => nil,
    }
  }

  it 'creates a notification rule'

  it "does not create a notification rule for a contact that doesn't exist"

  it "gets all notification rules" do
    expect(Flapjack::Data::NotificationRule).to receive(:all).
      and_return([notification_rule])

    expect(notification_rule).to receive(:as_json).and_return(notification_rule_data)
    expect(Flapjack::Data::NotificationRule).to receive(:associated_ids_for_contact).
      with([notification_rule.id]).and_return({notification_rule.id => contact.id})
    expect(Flapjack::Data::NotificationRule).to receive(:associated_ids_for_states).
      with([notification_rule.id]).and_return({})

    get "/notification_rules"
    expect(last_response).to be_ok
    expect(last_response.body).to eq({:notification_rules => [notification_rule_data]}.to_json)
  end

  it "gets a single notification rule" do
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_ids!).
      with([notification_rule.id]).and_return([notification_rule])

    expect(notification_rule).to receive(:as_json).and_return(notification_rule_data)
    expect(Flapjack::Data::NotificationRule).to receive(:associated_ids_for_contact).
      with([notification_rule.id]).and_return({notification_rule.id => contact.id})
    expect(Flapjack::Data::NotificationRule).to receive(:associated_ids_for_states).
      with([notification_rule.id]).and_return({})

    get "/notification_rules/#{notification_rule.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq({:notification_rules => [notification_rule_data]}.to_json)
  end

  it "does not get a notification rule that does not exist" do
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_ids!).
      with([notification_rule.id]).
      and_raise(Sandstorm::Errors::RecordsNotFound.new(Flapjack::Data::NotificationRule, [notification_rule.id]))

    get "/notification_rules/#{notification_rule.id}"
    expect(last_response).to be_not_found
  end

  it "updates a notification rule" do
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_ids!).
      with([notification_rule.id]).and_return([notification_rule])

    expect(notification_rule).to receive(:tags=).with([])
    expect(notification_rule).to receive(:save).and_return(true)

    patch "/notification_rules/#{notification_rule.id}",
      [{:op => 'replace', :path => '/notification_rules/0/tags', :value => []}].to_json,
      jsonapi_patch_env
    expect(last_response.status).to eq(204)
  end

  it "updates multiple notification rules" do
    notification_rule_2 = double(Flapjack::Data::NotificationRule, :id => 'uiop')
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_ids!).
      with([notification_rule.id, notification_rule_2.id]).and_return([notification_rule, notification_rule_2])

    expect(notification_rule).to receive(:tags=).with(['new'])
    expect(notification_rule).to receive(:save).and_return(true)

    expect(notification_rule_2).to receive(:tags=).with(['new'])
    expect(notification_rule_2).to receive(:save).and_return(true)

    patch "/notification_rules/#{notification_rule.id},#{notification_rule_2.id}",
      [{:op => 'replace', :path => '/notification_rules/0/tags', :value => ['new']}].to_json,
      jsonapi_patch_env
    expect(last_response.status).to eq(204)
  end

  it "does not update a notification rule that does not exist" do
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_ids!).with([notification_rule.id]).
      and_raise(Sandstorm::Errors::RecordsNotFound.new(Flapjack::Data::NotificationRule, [notification_rule.id]))

    patch "/notification_rules/#{notification_rule.id}",
      [{:op => 'replace', :path => '/notification_rules/0/regex_tags', :value => ['.*']}].to_json,
      jsonapi_patch_env
    expect(last_response).to be_not_found
  end

  it "deletes a notification rule" do
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_ids!).
      with([notification_rule.id]).and_return([notification_rule])

    expect(notification_rule).to receive(:destroy)

    delete "/notification_rules/#{notification_rule.id}"
    expect(last_response.status).to eq(204)
  end

  it "deletes multiple notification rules" do
    notification_rule_2 = double(Flapjack::Data::NotificationRule, :id => 'uiop')
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_ids!).
      with([notification_rule.id, notification_rule_2.id]).and_return([notification_rule, notification_rule_2])

    expect(notification_rule).to receive(:destroy)
    expect(notification_rule_2).to receive(:destroy)

    delete "/notification_rules/#{notification_rule.id},#{notification_rule_2.id}"
    expect(last_response.status).to eq(204)
  end

  it "does not delete a notification rule that does not exist" do
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_ids!).with([notification_rule.id]).
      and_raise(Sandstorm::Errors::RecordsNotFound.new(Flapjack::Data::NotificationRule, [notification_rule.id]))

    delete "/notification_rules/#{notification_rule.id}"
    expect(last_response).to be_not_found
  end

end
