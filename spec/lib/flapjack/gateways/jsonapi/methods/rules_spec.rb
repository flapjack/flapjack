require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::Rules', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:rule)    { double(Flapjack::Data::Rule, :id => rule_data[:id]) }
  let(:rule_2)  { double(Flapjack::Data::Rule, :id => rule_2_data[:id]) }

  let(:contact) { double(Flapjack::Data::Contact, :id => contact_data[:id]) }

  let(:medium)  { double(Flapjack::Data::Medium, :id => email_data[:id]) }

  it "creates a rule" do
    expect(Flapjack::Data::Rule).to receive(:lock).
      with(no_args).
      and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => [rule_data[:id]]).and_return(empty_ids)

    expect(rule).to receive(:invalid?).and_return(false)
    expect(rule).to receive(:save!).and_return(true)
    expect(Flapjack::Data::Rule).to receive(:new).with(rule_data).
      and_return(rule)

    expect(rule).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(rule_data.reject {|k,v| :id.eql?(k)})

    req_data  = rule_json(rule_data)
    resp_data = req_data.merge(:relationships => rule_rel(rule_data))

    post "/rules", Flapjack.dump_json(:data => req_data), jsonapi_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data =>
      resp_data))
  end

  it "does not create a rule if the data is improperly formatted" do
    expect(Flapjack::Data::Rule).to receive(:lock).
      with(no_args).
      and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => [rule_data[:id]]).and_return(empty_ids)

    errors = double('errors', :full_messages => ['err'])
    expect(rule).to receive(:errors).and_return(errors)

    expect(rule).to receive(:invalid?).and_return(true)
    expect(rule).not_to receive(:save!)
    expect(Flapjack::Data::Rule).to receive(:new).with(rule_data).
      and_return(rule)

    req_data  = rule_json(rule_data)

    post "/rules", Flapjack.dump_json(:data => req_data), jsonapi_env
    expect(last_response.status).to eq(403)
  end

  it "gets all rules" do
    expect(Flapjack::Data::Rule).to receive(:lock).
      with(no_args).
      and_yield

    meta = {
      :pagination => {
        :page        => 1,
        :per_page    => 20,
        :total_pages => 1,
        :total_count => 1
      }
    }

    links = {
      :self  => 'http://example.org/rules',
      :first => 'http://example.org/rules?page=1',
      :last  => 'http://example.org/rules?page=1'
    }

    page = double('page')
    expect(page).to receive(:empty?).and_return(false)
    expect(page).to receive(:ids).and_return([rule.id])
    expect(page).to receive(:collect) {|&arg| [arg.call(rule)] }
    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).
      and_return(page)
    expect(sorted).to receive(:count).and_return(1)
    expect(Flapjack::Data::Rule).to receive(:sort).
      with(:id).and_return(sorted)

    expect(rule).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(rule_data.reject {|k,v| :id.eql?(k)})

    resp_data = [rule_json(rule_data).merge(:relationships => rule_rel(rule_data))]

    get '/rules'
    expect(last_response).to be_ok
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data => resp_data,
      :links => links, :meta => meta))
  end

  it "gets a single rule" do
    expect(Flapjack::Data::Rule).to receive(:lock).
      with(no_args).
      and_yield

    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => Set.new([rule.id])).and_return([rule])

    expect(rule).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(rule_data.reject {|k,v| :id.eql?(k)})

    resp_data = rule_json(rule_data).merge(:relationships => rule_rel(rule_data))

    get "/rules/#{rule.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data =>
      resp_data, :links => {:self  => "http://example.org/rules/#{rule.id}"}))
  end

  it "does not get a rule that does not exist" do
    expect(Flapjack::Data::Rule).to receive(:lock).
      with(no_args).
      and_yield

    no_rules = double('no_rules')
    expect(no_rules).to receive(:empty?).and_return(true)

    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => Set.new([rule.id])).and_return(no_rules)

    get "/rules/#{rule.id}"
    expect(last_response).to be_not_found
  end

  it "retrieves a rule and its linked contact record" do
    expect(Flapjack::Data::Rule).to receive(:lock).
      with(Flapjack::Data::Contact).
      and_yield

    rules = double('rules')
    expect(rules).to receive(:empty?).and_return(false)
    expect(rules).to receive(:collect) {|&arg| [arg.call(rule)] }
    expect(rules).to receive(:associated_ids_for).with(:contact).
      and_return(rule.id => contact.id)
    expect(rules).to receive(:ids).and_return(Set.new([rule.id]))
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => Set.new([rule.id])).twice.and_return(rules)

    contacts = double('contacts')
    expect(contacts).to receive(:collect) {|&arg| [arg.call(contact)] }
    expect(Flapjack::Data::Contact).to receive(:intersect).
      with(:id => [contact.id]).and_return(contacts)

    expect(contact).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(contact_data.reject {|k,v| :id.eql?(k)})

    expect(rule).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(rule_data.reject {|k,v| :id.eql?(k)})

    get "/rules/#{rule.id}?include=contact"
    expect(last_response).to be_ok

    resp_data = rule_json(rule_data).merge(:relationships => rule_rel(rule_data))
    resp_data[:relationships][:contact][:data] = {:type => 'contact', :id => contact.id}

    resp_included = [contact_json(contact_data)]

    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data => resp_data,
      :included => resp_included,
      :links => {:self  => "http://example.org/rules/#{rule.id}?include=contact"}))
  end

  it "retrieves a rule, its contact, and all of its contact's media records" do
    expect(Flapjack::Data::Rule).to receive(:lock).
      with(Flapjack::Data::Contact,
           Flapjack::Data::Medium).
      and_yield

    rules = double('rules')
    expect(rules).to receive(:empty?).and_return(false)
    expect(rules).to receive(:collect) {|&arg| [arg.call(rule)] }
    expect(rules).to receive(:associated_ids_for).with(:contact).
      and_return(rule.id => contact.id)
    expect(rules).to receive(:ids).and_return(Set.new([rule.id]))
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => Set.new([rule.id])).twice.and_return(rules)

    contacts = double('contacts')
    expect(contacts).to receive(:collect) {|&arg| [arg.call(contact)] }
    expect(contacts).to receive(:associated_ids_for).with(:media).
      and_return({contact.id => [medium.id]})
    expect(Flapjack::Data::Contact).to receive(:intersect).
      with(:id => [contact_data[:id]]).twice.and_return(contacts)

    media = double('media')
    expect(media).to receive(:collect) {|&arg| [arg.call(medium)] }
    expect(Flapjack::Data::Medium).to receive(:intersect).
      with(:id => [medium.id]).and_return(media)

    expect(medium).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(email_data.reject {|k,v| :id.eql?(k)})

    expect(contact).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(contact_data.reject {|k,v| :id.eql?(k)})

    expect(rule).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(rule_data.reject {|k,v| :id.eql?(k)})

    get "/rules/#{rule.id}?include=contact.media"
    expect(last_response).to be_ok

    resp_data = rule_json(rule_data).merge(:relationships => rule_rel(rule_data))
    resp_data[:relationships][:contact][:data] = {:type => 'contact', :id => contact.id}

    resp_incl_contact = contact_json(contact_data)
    resp_incl_contact[:relationships] = {:media => {:data => [{:type => 'medium', :id => medium.id}]}}

    resp_included = [
      resp_incl_contact,
      medium_json(email_data)
    ]

    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data => resp_data,
      :included => resp_included,
      :links => {:self  => "http://example.org/rules/#{rule.id}?include=contact.media"}
    ))
  end

  it "deletes a rule" do
    expect(Flapjack::Data::Rule).to receive(:lock).
      with(Flapjack::Data::Contact,
           Flapjack::Data::Medium,
           Flapjack::Data::Tag).
      and_yield

    expect(rule).to receive(:destroy)
    expect(Flapjack::Data::Rule).to receive(:find_by_id!).
      with(rule.id).and_return(rule)

    delete "/rules/#{rule.id}"
    expect(last_response.status).to eq(204)
  end

  it "deletes multiple rules" do
    expect(Flapjack::Data::Rule).to receive(:lock).
      with(Flapjack::Data::Contact,
           Flapjack::Data::Medium,
           Flapjack::Data::Tag).
      and_yield

    rules = double('rules')
    expect(rules).to receive(:count).and_return(2)
    expect(rules).to receive(:destroy_all)
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => [rule.id, rule_2.id]).and_return(rules)

    delete "/rules",
      Flapjack.dump_json(:data => [
        {:id => rule.id, :type => 'rule'},
        {:id => rule_2.id, :type => 'rule'}
      ]),
      jsonapi_bulk_env
    expect(last_response.status).to eq(204)
  end

  it "does not delete a rule that does not exist" do
    expect(Flapjack::Data::Rule).to receive(:lock).
      with(Flapjack::Data::Contact,
           Flapjack::Data::Medium,
           Flapjack::Data::Tag).
      and_yield

    expect(Flapjack::Data::Rule).to receive(:find_by_id!).
      with(rule.id).and_raise(Zermelo::Records::Errors::RecordNotFound.new(Flapjack::Data::Rule, rule.id))

    delete "/rules/#{rule.id}"
    expect(last_response).to be_not_found
  end

end
