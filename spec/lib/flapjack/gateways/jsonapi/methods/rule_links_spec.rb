require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::RuleLinks', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:rule)    { double(Flapjack::Data::Rule, :id => rule_data[:id]) }
  let(:contact) { double(Flapjack::Data::Contact, :id => contact_data[:id]) }
  let(:tag)     { double(Flapjack::Data::Tag, :id => tag_data[:name]) }
  let(:route)   { double(Flapjack::Data::Route, :id => route_data[:id]) }

  let(:rule_tags)   { double('rule_tags') }
  let(:rule_routes) { double('rule_routes') }

  it 'sets a contact for a rule' do
    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule.id).
      and_return(rule)
    expect(Flapjack::Data::Contact).to receive(:find_by_id!).with(contact.id).
      and_return(contact)

    expect(rule).to receive(:contact).and_return(nil)
    expect(rule).to receive(:contact=).with(contact)

    post "/rules/#{rule.id}/links/contact", Flapjack.dump_json(:contact => contact.id), jsonapi_post_env
    expect(last_response.status).to eq(204)
  end

  it 'shows the contact for a rule' do
    expect(rule).to receive(:contact).and_return(contact)

    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule.id).
      and_return(rule)

    get "/rules/#{rule.id}/links/contact"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to eq(Flapjack.dump_json(:contact => contact.id))
  end

  it 'changes the contact for a rule' do
    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule.id).
      and_return(rule)
    expect(Flapjack::Data::Contact).to receive(:find_by_id!).with(contact.id).
      and_return(contact)

    expect(rule).to receive(:contact=).with(contact)

    put "/rules/#{rule.id}/links/contact", Flapjack.dump_json(:contact => contact.id), jsonapi_put_env
    expect(last_response.status).to eq(204)
  end

  it 'clears the contact for a rule' do
    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule.id).
      and_return(rule)

    expect(rule).to receive(:contact).and_return(contact)
    expect(rule).to receive(:contact=).with(nil)

    delete "/rules/#{rule.id}/links/contact"
    expect(last_response.status).to eq(204)
  end

  it 'adds a route to a rule' do
    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule.id).
      and_return(rule)
    expect(Flapjack::Data::Route).to receive(:find_by_ids!).with(route.id).
      and_return([route])

    expect(rule_routes).to receive(:add).with(route)
    expect(rule).to receive(:routes).and_return(rule_routes)

    post "/rules/#{rule.id}/links/routes", Flapjack.dump_json(:routes => route.id), jsonapi_post_env
    expect(last_response.status).to eq(204)
  end

  it 'lists routes for a rule' do
    expect(rule_routes).to receive(:ids).and_return([route.id])
    expect(rule).to receive(:routes).and_return(rule_routes)

    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule.id).
      and_return(rule)

    get "/rules/#{rule.id}/links/routes"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to eq(Flapjack.dump_json(:routes => [route.id]))
  end

  it 'updates routes for a rule' do
    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule.id).
      and_return(rule)
    expect(Flapjack::Data::Route).to receive(:find_by_ids!).with(route.id).
      and_return([route])

    expect(rule_routes).to receive(:ids).and_return([])
    expect(rule_routes).to receive(:add).with(route)
    expect(rule).to receive(:routes).twice.and_return(rule_routes)

    put "/rules/#{rule.id}/links/routes", Flapjack.dump_json(:routes => [route.id]), jsonapi_put_env
    expect(last_response.status).to eq(204)
  end

  it 'deletes a route from a rule' do
    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule.id).
      and_return(rule)

    expect(rule_routes).to receive(:find_by_ids!).with(route.id).
      and_return([route])
    expect(rule_routes).to receive(:delete).with(route)
    expect(rule).to receive(:routes).and_return(rule_routes)

    delete "/rules/#{rule.id}/links/routes/#{route.id}"
    expect(last_response.status).to eq(204)
  end

  it 'adds tags to a rule' do
    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule.id).
      and_return(rule)
    expect(Flapjack::Data::Tag).to receive(:find_by_ids!).with(tag.id).
      and_return([tag])

    expect(rule_tags).to receive(:add).with(tag)
    expect(rule).to receive(:tags).and_return(rule_tags)

    post "/rules/#{rule.id}/links/tags", Flapjack.dump_json(:tags => tag.id), jsonapi_post_env
    expect(last_response.status).to eq(204)
  end

  it 'lists tags for a rule' do
    expect(rule_tags).to receive(:ids).and_return([tag.id])
    expect(rule).to receive(:tags).and_return(rule_tags)

    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule.id).
      and_return(rule)

    get "/rules/#{rule.id}/links/tags"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to eq(Flapjack.dump_json(:tags => [tag.id]))
  end

  it 'updates tags for a rule' do
    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule.id).
      and_return(rule)
    expect(Flapjack::Data::Tag).to receive(:find_by_ids!).with(tag.id).
      and_return([tag])

    expect(rule_tags).to receive(:ids).and_return([])
    expect(rule_tags).to receive(:add).with(tag)
    expect(rule).to receive(:tags).twice.and_return(rule_tags)

    put "/rules/#{rule.id}/links/tags", Flapjack.dump_json(:tags => [tag.id]), jsonapi_put_env
    expect(last_response.status).to eq(204)
  end

  it 'deletes a tag from a rule' do
    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule.id).
      and_return(rule)

    expect(rule_tags).to receive(:find_by_ids!).with(tag.id).
      and_return([tag])
    expect(rule_tags).to receive(:delete).with(tag)
    expect(rule).to receive(:tags).and_return(rule_tags)

    delete "/rules/#{rule.id}/links/tags/#{tag.id}"
    expect(last_response.status).to eq(204)
  end

end
