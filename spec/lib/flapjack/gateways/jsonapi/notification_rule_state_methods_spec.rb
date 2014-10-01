require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::NotificationRuleStateMethods', :sinatra => true, :logger => true do

  include_context "jsonapi"

  let (:notification_rule_state) {
    double(Flapjack::Data::NotificationRuleState, :id => '8')
  }

  let(:notification_rule_state_data) {
    {'state'     => 'critical',
     'blackhole' => false}
  }

  let (:notification_rule) {
    double(Flapjack::Data::NotificationRule, :id => '1')
  }

  it "gets all notification rule states" do
    expect(Flapjack::Data::NotificationRuleState).to receive(:all).
      and_return([notification_rule_state])

    expect(notification_rule_state).to receive(:as_json).and_return(notification_rule_state_data)
    expect(Flapjack::Data::NotificationRuleState).to receive(:associated_ids_for_notification_rule).
      with(notification_rule_state.id).and_return({notification_rule_state.id => notification_rule.id})

    get "/notification_rule_states"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:notification_rule_states => [notification_rule_state_data]))
  end

  it "gets a single notification rule state" do
    expect(Flapjack::Data::NotificationRuleState).to receive(:find_by_ids!).
      with(notification_rule_state.id).and_return([notification_rule_state])

    expect(notification_rule_state).to receive(:as_json).and_return(notification_rule_state_data)
    expect(Flapjack::Data::NotificationRuleState).to receive(:associated_ids_for_notification_rule).
      with(notification_rule_state.id).and_return({notification_rule_state.id => notification_rule.id})

    get "/notification_rule_states/#{notification_rule_state.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:notification_rule_states => [notification_rule_state_data]))
  end

  it "does not get a notification rule state that does not exist" do
    expect(Flapjack::Data::NotificationRuleState).to receive(:find_by_ids!).
      with(notification_rule_state.id).
      and_raise(Sandstorm::Records::Errors::RecordsNotFound.new(Flapjack::Data::NotificationRuleState, [notification_rule_state.id]))

    get "/notification_rule_states/#{notification_rule_state.id}"
    expect(last_response).to be_not_found
  end

  it "updates a notification rule state" do
    expect(Flapjack::Data::NotificationRuleState).to receive(:find_by_ids!).
      with(notification_rule_state.id).and_return([notification_rule_state])

    expect(notification_rule_state).to receive(:blackhole=).with(true)
    expect(notification_rule_state).to receive(:save).and_return(true)

    patch "/notification_rule_states/#{notification_rule_state.id}",
      Flapjack.dump_json([{:op => 'replace', :path => '/notification_rule_states/0/blackhole', :value => true}]),
      jsonapi_patch_env
    expect(last_response.status).to eq(204)
  end

  it "updates multiple notification rule states" do
    notification_rule_state_2 = double(Flapjack::Data::NotificationRuleState, :id => 'uiop')
    expect(Flapjack::Data::NotificationRuleState).to receive(:find_by_ids!).
      with(notification_rule_state.id, notification_rule_state_2.id).and_return([notification_rule_state, notification_rule_state_2])

    expect(notification_rule_state).to receive(:blackhole=).with(true)
    expect(notification_rule_state).to receive(:save).and_return(true)

    expect(notification_rule_state_2).to receive(:blackhole=).with(true)
    expect(notification_rule_state_2).to receive(:save).and_return(true)

    patch "/notification_rule_states/#{notification_rule_state.id},#{notification_rule_state_2.id}",
      Flapjack.dump_json([{:op => 'replace', :path => '/notification_rule_states/0/blackhole', :value => true}]),
      jsonapi_patch_env
    expect(last_response.status).to eq(204)
  end

  it "does not update a notification rule state that does not exist" do
    expect(Flapjack::Data::NotificationRuleState).to receive(:find_by_ids!).
      with(notification_rule_state.id).
      and_raise(Sandstorm::Records::Errors::RecordsNotFound.new(Flapjack::Data::NotificationRuleState, [notification_rule_state.id]))

    patch "/notification_rule_states/#{notification_rule_state.id}",
      Flapjack.dump_json([{:op => 'replace', :path => '/notification_rule_states/0/blackhole', :value => true}]),
      jsonapi_patch_env
    expect(last_response).to be_not_found
  end

end
