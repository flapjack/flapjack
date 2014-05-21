require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::NotificationRuleMethods', :sinatra => true, :logger => true do

  include_context "jsonapi"

  let(:contact)      { double(Flapjack::Data::Contact, :id => '21') }

  let(:notification_rule) {
    double(Flapjack::Data::NotificationRule, :id => '1', :contact_id => '21')
  }

  let(:notification_rule_data) {
    {"tags"               => ["database","physical"],
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

  it "returns a specified notification rule" do
    expect(notification_rule).to receive(:to_jsonapi).and_return('"rule_1"')
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_id).
      with(notification_rule.id, :redis => redis, :logger => @logger).and_return(notification_rule)

    aget "/notification_rules/#{notification_rule.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq('{"notification_rules":["rule_1"]}')
  end

  it "returns multiple notification rules" do
    notification_rule_2 = double(Flapjack::Data::NotificationRule, :id => '2', :contact_id => '21')

    expect(notification_rule).to receive(:to_jsonapi).and_return('"rule_1"')
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_id).
      with(notification_rule.id, :redis => redis, :logger => @logger).and_return(notification_rule)

    expect(notification_rule_2).to receive(:to_jsonapi).and_return('"rule_2"')
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_id).
      with(notification_rule_2.id, :redis => redis, :logger => @logger).and_return(notification_rule_2)

    aget "/notification_rules/#{notification_rule.id},#{notification_rule_2.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq('{"notification_rules":["rule_1", "rule_2"]}')
  end

  it "returns all notification rules" do
    expect(notification_rule).to receive(:to_jsonapi).and_return('"rule_1"')
    expect(Flapjack::Data::NotificationRule).to receive(:all).
      with(:redis => redis).and_return([notification_rule])

    aget "/notification_rules"
    expect(last_response).to be_ok
    expect(last_response.body).to eq('{"notification_rules":["rule_1"]}')
  end

  it "skips notification rules without ids when getting all" do
    idless_notification_rule = double(Flapjack::Data::NotificationRule, :id => '')

    expect(notification_rule).to receive(:to_jsonapi).and_return('"rule_1"')
    expect(idless_notification_rule).not_to receive(:to_jsonapi)
    expect(Flapjack::Data::NotificationRule).to receive(:all).with(:redis => redis).
      and_return([notification_rule, idless_notification_rule])

    aget '/notification_rules'
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

    # symbolize the keys
    notification_rule_data_sym = notification_rule_data.inject({}){|memo,(k,v)|
      memo[k.to_sym] = v; memo
    }

    expect(contact).to receive(:add_notification_rule).
      with(notification_rule_data_sym, :logger => @logger).and_return(notification_rule)

    apost "/contacts/#{contact.id}/notification_rules",
      {"notification_rules" => [notification_rule_data]}.to_json, jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.headers['Location']).to match(/\/notification_rules\/.+$/)
  end

  it "does not create a notification_rule for a contact that's not present" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(nil)

    apost "/contacts/#{contact.id}/notification_rules",
      {"notification_rules" => [notification_rule_data]}.to_json, jsonapi_post_env
    expect(last_response.status).to eq(404)
  end

  # PATCH /notification_rules/RULE_ID
  it "updates a notification rule" do
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_id).
      with(notification_rule.id, {:redis => redis, :logger => @logger}).and_return(notification_rule)

    expect(notification_rule).to receive(:update).with({:warning_blackhole => true}, :logger => @logger).and_return(nil)

    apatch "/notification_rules/#{notification_rule.id}",
      [{:op => 'replace', :path => '/notification_rules/0/warning_blackhole', :value => true}].to_json,
      jsonapi_patch_env
    expect(last_response.status).to eq(204)
  end

  it "does not update a notification rule that's not present" do
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_id).
      with(notification_rule.id, {:redis => redis, :logger => @logger}).and_return(nil)

    apatch "/notification_rules/#{notification_rule.id}",
      [{:op => 'replace', :path => '/notification_rules/0/warning_blackhole', :value => true}].to_json,
      jsonapi_patch_env
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

end
