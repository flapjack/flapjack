require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::Rules', :sinatra => true, :logger => true do

  before { skip 'broken, fixing' }

  include_context "jsonapi"

  let (:rule) {
    double(Flapjack::Data::Rule, :id => '1')
  }

  let(:rule_data) {
    {}
  }

  let(:contact)      { double(Flapjack::Data::Contact, :id => '21') }

  it "creates a rule" do
    expect(Flapjack::Data::Contact).to receive(:lock).
      with(Flapjack::Data::Rule).and_yield

    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id).and_return(contact)

    expect(rule).to receive(:invalid?).and_return(false)
    expect(rule).to receive(:save).and_return(true)
    expect(Flapjack::Data::Rule).to receive(:new).
      with(rule_data.merge(:id => nil, :is_specific => false)).and_return(rule)

    contact_rules = ('contact_rules')
    expect(contact).to receive(:rules).and_return(contact_rules)
    expect(contact_rules).to receive(:"<<").with(rule)

    post "/contacts/#{contact.id}/rules",
      Flapjack.dump_json(:rules => [rule_data]), jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json([rule.id]))
  end

  it "does not create a rule if the data is improperly formatted" do
    expect(Flapjack::Data::Contact).to receive(:lock).
      with(Flapjack::Data::Rule).and_yield

    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id).and_return(contact)

    errors = double('errors', :full_messages => ['err'])
    expect(rule).to receive(:errors).and_return(errors)

    expect(rule).to receive(:invalid?).and_return(true)
    expect(rule).not_to receive(:save)
    expect(Flapjack::Data::Rule).to receive(:new).and_return(rule)

    post "/contacts/#{contact.id}/rules",
      Flapjack.dump_json(:rules => [{'silly' => 'sausage'}]), jsonapi_post_env
    expect(last_response.status).to eq(403)
  end

  it "does not create a rule if the contact doesn't exist" do
    expect(Flapjack::Data::Contact).to receive(:lock).
      with(Flapjack::Data::Rule).and_yield

    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id).and_return(nil)

    post "/contacts/#{contact.id}/rules",
      Flapjack.dump_json(:rules => [rule_data]), jsonapi_post_env
    expect(last_response.status).to eq(403)
  end

  it "gets all notification rules" do

    expect(Flapjack::Data::Rule).to receive(:count).and_return(1)

    meta = {:pagination => {
      :page        => 1,
      :per_page    => 20,
      :total_pages => 1,
      :total_count => 1
    }}

    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).
      and_return([rule])
    expect(Flapjack::Data::Rule).to receive(:sort).
      with(:id, :order => 'alpha').and_return(sorted)

    expect(rule).to receive(:as_json).and_return(rule_data)

    rule_ids = double('rule_ids')
    expect(rule_ids).to receive(:associated_ids_for).with(:contact).
      and_return(rule.id => contact.id)
    expect(rule_ids).to receive(:associated_ids_for).with(:tags).
      and_return({})
    expect(rule_ids).to receive(:associated_ids_for).with(:routes).
      and_return({})
    expect(Flapjack::Data::Rule).to receive(:intersect).with(:id => [rule.id]).
      exactly(3).times.and_return(rule_ids)

    get "/rules"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:rules => [rule_data], :meta => meta))
  end

  it "gets a single notification rule" do
    expect(Flapjack::Data::Rule).to receive(:find_by_ids!).
      with(rule.id).and_return([rule])

    expect(rule).to receive(:as_json).and_return(rule_data)

    rule_ids = double('rule_ids')
    expect(rule_ids).to receive(:associated_ids_for).with(:contact).
      and_return(rule.id => contact.id)
    expect(rule_ids).to receive(:associated_ids_for).with(:tags).
      and_return({})
    expect(rule_ids).to receive(:associated_ids_for).with(:routes).
      and_return({})
    expect(Flapjack::Data::Rule).to receive(:intersect).with(:id => [rule.id]).
      exactly(3).times.and_return(rule_ids)

    get "/rules/#{rule.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:rules => [rule_data]))
  end

  it "does not get a notification rule that does not exist" do
    expect(Flapjack::Data::Rule).to receive(:find_by_ids!).
      with(rule.id).
      and_raise(Sandstorm::Records::Errors::RecordsNotFound.new(Flapjack::Data::Rule, [rule.id]))

    get "/rules/#{rule.id}"
    expect(last_response).to be_not_found
  end

  it "updates a notification rule" do
    expect(Flapjack::Data::Rule).to receive(:find_by_ids!).
      with(rule.id).and_return([rule])

    expect(rule).to receive(:time_restrictions=).with([])
    expect(rule).to receive(:save).and_return(true)

    patch "/rules/#{rule.id}",
      Flapjack.dump_json([{:op => 'replace', :path => '/rules/0/time_restrictions', :value => []}]),
      jsonapi_patch_env
    expect(last_response.status).to eq(204)
  end

  it "updates multiple notification rules" do
    rule_2 = double(Flapjack::Data::Rule, :id => 'uiop')
    expect(Flapjack::Data::Rule).to receive(:find_by_ids!).
      with(rule.id, rule_2.id).and_return([rule, rule_2])

    expect(rule).to receive(:time_restrictions=).with([])
    expect(rule).to receive(:save).and_return(true)

    expect(rule_2).to receive(:time_restrictions=).with([])
    expect(rule_2).to receive(:save).and_return(true)

    patch "/rules/#{rule.id},#{rule_2.id}",
      Flapjack.dump_json([{:op => 'replace', :path => '/rules/0/time_restrictions', :value => []}]),
      jsonapi_patch_env
    expect(last_response.status).to eq(204)
  end

  it "does not update a notification rule that does not exist" do
    expect(Flapjack::Data::Rule).to receive(:find_by_ids!).
      with(rule.id).
      and_raise(Sandstorm::Records::Errors::RecordsNotFound.new(Flapjack::Data::Rule, [rule.id]))

    patch "/rules/#{rule.id}",
      Flapjack.dump_json([{:op => 'replace', :path => '/rules/0/time_restrictions', :value => []}]),
      jsonapi_patch_env
    expect(last_response).to be_not_found
  end

  it "deletes a notification rule" do
    rules = double('rules')
    expect(rules).to receive(:ids).and_return([rule.id])
    expect(rules).to receive(:destroy_all)
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => [rule.id]).and_return(rules)

    delete "/rules/#{rule.id}"
    expect(last_response.status).to eq(204)
  end

  it "deletes multiple notification rules" do
    rule_2 = double(Flapjack::Data::Rule, :id => 'uiop')
    rules = double('rules')
    expect(rules).to receive(:ids).
      and_return([rule.id, rule_2.id])
    expect(rules).to receive(:destroy_all)
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => [rule.id, rule_2.id]).
      and_return(rules)

    delete "/rules/#{rule.id},#{rule_2.id}"
    expect(last_response.status).to eq(204)
  end

  it "does not delete a notification rule that does not exist" do
    rules = double('rules')
    expect(rules).to receive(:ids).and_return([])
    expect(rules).not_to receive(:destroy_all)
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => [rule.id]).and_return(rules)

    delete "/rules/#{rule.id}"
    expect(last_response).to be_not_found
  end

end
