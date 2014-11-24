require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::Rules', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:rule)    { double(Flapjack::Data::Rule, :id => rule_data[:id]) }
  let(:rule_2)  { double(Flapjack::Data::Rule, :id => rule_2_data[:id]) }

  let(:contact) { double(Flapjack::Data::Contact, :id => contact_data[:id]) }

  let(:medium)  { double(Flapjack::Data::Medium, :id => email_data[:id]) }
  let(:route)   { double(Flapjack::Data::Route, :id => route_data[:id]) }

  it "creates a rule" do
    expect(Flapjack::Data::Rule).to receive(:lock).with(Flapjack::Data::Contact,
      Flapjack::Data::Tag).and_yield
    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => [rule_data[:id]]).and_return(empty_ids)

    expect(rule).to receive(:invalid?).and_return(false)
    expect(rule).to receive(:save).and_return(true)
    expect(Flapjack::Data::Rule).to receive(:new).with(rule_data).
      and_return(rule)

    expect(Flapjack::Data::Rule).to receive(:as_jsonapi).
      with(:resources => [rule], :ids => [rule.id], :unwrap => true).
      and_return(rule_data)

    post "/rules", Flapjack.dump_json(:rules => rule_data), jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json(:rules => rule_data))
  end

  it "does not create a rule if the data is improperly formatted" do
    expect(Flapjack::Data::Rule).to receive(:lock).with(Flapjack::Data::Contact,
      Flapjack::Data::Tag).and_yield
    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => [rule_data[:id]]).and_return(empty_ids)

    errors = double('errors', :full_messages => ['err'])
    expect(rule).to receive(:errors).and_return(errors)

    expect(rule).to receive(:invalid?).and_return(true)
    expect(rule).not_to receive(:save)
    expect(Flapjack::Data::Rule).to receive(:new).with(rule_data).
      and_return(rule)

    expect(Flapjack::Data::Rule).not_to receive(:as_jsonapi)

    post "/rules", Flapjack.dump_json(:rules => rule_data), jsonapi_post_env
    expect(last_response.status).to eq(403)
  end

  it "creates a rule linked to a contact" do
    expect(Flapjack::Data::Rule).to receive(:lock).
      with(Flapjack::Data::Contact, Flapjack::Data::Tag).and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => [rule_data[:id]]).and_return(empty_ids)

    rule_with_contact_data = rule_data.merge(:links => {
      :contact => contact_data[:id]
    })

    expect(Flapjack::Data::Contact).to receive(:find_by_id!).with(contact_data[:id]).
      and_return(contact)

    expect(rule).to receive(:invalid?).and_return(false)
    expect(rule).to receive(:save).and_return(true)
    expect(rule).to receive(:contact=).with(contact)
    expect(Flapjack::Data::Rule).to receive(:new).with(rule_data).
      and_return(rule)

    expect(Flapjack::Data::Rule).to receive(:as_jsonapi).
      with(:resources => [rule], :ids => [rule.id], :unwrap => true).
      and_return(rule_with_contact_data)

    post "/rules", Flapjack.dump_json(:rules => rule_with_contact_data), jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json(:rules => rule_with_contact_data))
  end

  it "does not create a rule with a linked contact if the contact doesn't exist" do
    expect(Flapjack::Data::Rule).to receive(:lock).
      with(Flapjack::Data::Contact, Flapjack::Data::Tag).and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => [rule_data[:id]]).and_return(empty_ids)

    rule_with_contact_data = rule_data.merge(:links => {
      :contact => contact_data[:id]
    })

    expect(Flapjack::Data::Contact).to receive(:find_by_id!).with(contact_data[:id]).
      and_raise(Sandstorm::Records::Errors::RecordNotFound.new(Flapjack::Data::Contact, contact_data[:id]))

    expect(rule).to receive(:invalid?).and_return(false)
    expect(rule).not_to receive(:save)
    expect(rule).not_to receive(:contact=).with(contact)
    expect(Flapjack::Data::Rule).to receive(:new).with(rule_data).
      and_return(rule)

    expect(Flapjack::Data::Rule).not_to receive(:as_jsonapi)

    post "/rules", Flapjack.dump_json(:rules => rule_with_contact_data), jsonapi_post_env
    expect(last_response.status).to eq(404)
  end

  it "gets all rules" do
    meta = {
      :pagination => {
        :page        => 1,
        :per_page    => 20,
        :total_pages => 1,
        :total_count => 1
      }
    }

    expect(Flapjack::Data::Rule).to receive(:count).and_return(1)

    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).
      and_return([rule])
    expect(Flapjack::Data::Rule).to receive(:sort).
      with(:id).and_return(sorted)

    expect(Flapjack::Data::Rule).to receive(:as_jsonapi).
      with(:resources => [rule], :ids => [rule.id],
           :fields => an_instance_of(Array), :unwrap => false).
      and_return([rule_data])

    get '/rules'
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:rules => [rule_data], :meta => meta))
  end

  it "gets a single rule" do
    expect(Flapjack::Data::Rule).to receive(:find_by_id!).
      with(rule.id).and_return(rule)

    expect(Flapjack::Data::Rule).to receive(:as_jsonapi).
      with(:resources => [rule], :ids => [rule.id],
           :fields => an_instance_of(Array), :unwrap => true).
      and_return(rule_data)

    get "/rules/#{rule.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:rules => rule_data))
  end

  it "does not get a rule that does not exist" do
    expect(Flapjack::Data::Rule).to receive(:find_by_id!).
      with(rule.id).
      and_raise(Sandstorm::Records::Errors::RecordNotFound.new(Flapjack::Data::Rule, rule.id))

    get "/rules/#{rule.id}"
    expect(last_response).to be_not_found
  end

  it "retrieves a rule and all its linked media records (through routes)" do
    expect(Flapjack::Data::Rule).to receive(:find_by_id!).
      with(rule.id).and_return(rule)

    rule_with_route_data = rule_data.merge(:links => {:routes => [route.id]})

    rules = double('rules')
    expect(rules).to receive(:associated_ids_for).with(:routes).
      and_return(rule.id => [route.id])
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => [rule.id]).and_return(rules)

    routes = double('routes')
    expect(routes).to receive(:associated_ids_for).with(:media).
      and_return(route.id => [medium.id])
    expect(Flapjack::Data::Route).to receive(:intersect).
      with(:id => [route.id]).and_return(routes)

    expect(Flapjack::Data::Medium).to receive(:find_by_ids!).
      with(medium.id).and_return([medium])

    expect(Flapjack::Data::Medium).to receive(:as_jsonapi).
      with(:resources => [medium], :ids => [medium.id], :unwrap => false).
      and_return([email_data])

    expect(Flapjack::Data::Rule).to receive(:as_jsonapi).
      with(:resources => [rule], :ids => [rule.id], :unwrap => true,
           :fields => an_instance_of(Array)).
      and_return(rule_with_route_data)

    get "/rules/#{rule.id}?include=routes.media"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:rules => rule_with_route_data,
      :linked => {:media => [email_data]}))
  end

  it "retrieves a rule, its routes, and the routes' media records" do
    expect(Flapjack::Data::Rule).to receive(:find_by_id!).
      with(rule.id).and_return(rule)

    rule_with_route_data = rule_data.merge(:links => {:routes => [route.id]})

    rules = double('rules')
    expect(rules).to receive(:associated_ids_for).with(:routes).
      and_return(rule.id => [route.id])
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => [rule.id]).and_return(rules)

    routes = double('routes')
    expect(routes).to receive(:associated_ids_for).with(:media).
      and_return(route.id => [medium.id])
    expect(Flapjack::Data::Route).to receive(:intersect).
      with(:id => [route.id]).and_return(routes)

    expect(Flapjack::Data::Medium).to receive(:find_by_ids!).
      with(medium.id).and_return([medium])

    expect(Flapjack::Data::Medium).to receive(:as_jsonapi).
      with(:resources => [medium], :ids => [medium.id], :unwrap => false).
      and_return([email_data])

    expect(Flapjack::Data::Route).to receive(:find_by_ids!).
      with(route.id).and_return([route])

    expect(Flapjack::Data::Route).to receive(:as_jsonapi).
      with(:resources => [route], :ids => [route.id], :unwrap => false).
      and_return([route_data])

    expect(Flapjack::Data::Rule).to receive(:as_jsonapi).
      with(:resources => [rule], :ids => [rule.id], :unwrap => true,
           :fields => an_instance_of(Array)).
      and_return(rule_with_route_data)

    get "/rules/#{rule.id}?include=routes,routes.media"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:rules => rule_with_route_data,
      :linked => {:routes => [route_data], :media => [email_data]}))
  end

  it "sets a contact for a rule" do
    expect(Flapjack::Data::Rule).to receive(:find_by_ids!).
      with(rule.id).and_return([rule])

    expect(Flapjack::Data::Contact).to receive(:find_by_id!).with(contact_data[:id]).
      and_return(contact)

    expect(rule).to receive(:invalid?).and_return(false)
    expect(rule).to receive(:save).and_return(true)

    expect(rule).to receive(:contact=).with(contact)

    put "/rules/#{rule.id}",
      Flapjack.dump_json(:rules =>
        {:id => rule.id, :links => {:contact => contact.id}}
      ),
      jsonapi_put_env
    expect(last_response.status).to eq(204)
  end

  it "sets a contact for multiple rules" do
    expect(Flapjack::Data::Rule).to receive(:find_by_ids!).
      with(rule.id, rule_2.id).and_return([rule, rule_2])

    expect(Flapjack::Data::Contact).to receive(:find_by_id!).with(contact_data[:id]).
      twice.and_return(contact)

    expect(rule).to receive(:invalid?).and_return(false)
    expect(rule).to receive(:save).and_return(true)

    expect(rule_2).to receive(:invalid?).and_return(false)
    expect(rule_2).to receive(:save).and_return(true)

    expect(rule).to receive(:contact=).with(contact)
    expect(rule_2).to receive(:contact=).with(contact)

    put "/rules/#{rule.id},#{rule_2.id}",
      Flapjack.dump_json(:rules => [
        {:id => rule.id, :links => {:contact => contact.id}},
        {:id => rule_2.id, :links => {:contact => contact.id}}
      ]),
      jsonapi_put_env
    expect(last_response.status).to eq(204)
  end

  it "does not set a contact for a notification rule that does not exist" do
    expect(Flapjack::Data::Rule).to receive(:find_by_ids!).
      with(rule.id).
      and_raise(Sandstorm::Records::Errors::RecordsNotFound.new(Flapjack::Data::Rule, [rule.id]))

    put "/rules/#{rule.id}",
      Flapjack.dump_json(:rules =>
        {:id => rule.id, :links => {:contact => contact.id}}
      ),
      jsonapi_put_env
    expect(last_response.status).to eq(404)
  end

  it "deletes a rule" do
    rules = double('rules')
    expect(rules).to receive(:ids).and_return([rule.id])
    expect(rules).to receive(:destroy_all)
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => [rule.id]).and_return(rules)

    delete "/rules/#{rule.id}"
    expect(last_response.status).to eq(204)
  end

  it "deletes multiple rules" do
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

  it "does not delete a rule that does not exist" do
    rules = double('rules')
    expect(rules).to receive(:ids).and_return([])
    expect(rules).not_to receive(:destroy_all)
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => [rule.id]).and_return(rules)

    delete "/rules/#{rule.id}"
    expect(last_response).to be_not_found
  end

end
