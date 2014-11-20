require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::MediumLinks', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:medium)  { double(Flapjack::Data::Medium, :id => email_data[:id]) }
  let(:contact) { double(Flapjack::Data::Contact, :id => contact_data[:id]) }
  let(:route)   { double(Flapjack::Data::Route, :id => route_data[:id]) }

  let(:medium_routes)  { double('medium_routes') }

  it 'sets a contact for a medium' do
    expect(Flapjack::Data::Medium).to receive(:find_by_id!).with(medium.id).
      and_return(medium)
    expect(Flapjack::Data::Contact).to receive(:find_by_id!).with(contact.id).
      and_return(contact)

    expect(medium).to receive(:contact).and_return(nil)
    expect(medium).to receive(:contact=).with(contact)

    post "/media/#{medium.id}/links/contact", Flapjack.dump_json(:contact => contact.id), jsonapi_post_env
    expect(last_response.status).to eq(204)
  end

  it 'shows the contact for a medium' do
    expect(medium).to receive(:contact).and_return(contact)

    expect(Flapjack::Data::Medium).to receive(:find_by_id!).with(medium.id).
      and_return(medium)

    get "/media/#{medium.id}/links/contact"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to eq(Flapjack.dump_json(:contact => contact.id))
  end

  it 'changes the contact for a medium' do
    expect(Flapjack::Data::Medium).to receive(:find_by_id!).with(medium.id).
      and_return(medium)
    expect(Flapjack::Data::Contact).to receive(:find_by_id!).with(contact.id).
      and_return(contact)

    expect(medium).to receive(:contact=).with(contact)

    put "/media/#{medium.id}/links/contact", Flapjack.dump_json(:contact => contact.id), jsonapi_put_env
    expect(last_response.status).to eq(204)
  end

  it 'clears the contact for a medium' do
    expect(Flapjack::Data::Medium).to receive(:find_by_id!).with(medium.id).
      and_return(medium)

    expect(medium).to receive(:contact).and_return(contact)
    expect(medium).to receive(:contact=).with(nil)

    delete "/media/#{medium.id}/links/contact"
    expect(last_response.status).to eq(204)
  end

  it 'adds a route to a medium' do
    expect(Flapjack::Data::Medium).to receive(:find_by_id!).with(medium.id).
      and_return(medium)
    expect(Flapjack::Data::Route).to receive(:find_by_ids!).with(route.id).
      and_return([route])

    expect(medium_routes).to receive(:add).with(route)
    expect(medium).to receive(:routes).and_return(medium_routes)

    post "/media/#{medium.id}/links/routes", Flapjack.dump_json(:routes => route.id), jsonapi_post_env
    expect(last_response.status).to eq(204)
  end

  it 'lists routes for a medium' do
    expect(medium_routes).to receive(:ids).and_return([route.id])
    expect(medium).to receive(:routes).and_return(medium_routes)

    expect(Flapjack::Data::Medium).to receive(:find_by_id!).with(medium.id).
      and_return(medium)

    get "/media/#{medium.id}/links/routes"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to eq(Flapjack.dump_json(:routes => [route.id]))
  end

  it 'updates routes for a medium' do
    expect(Flapjack::Data::Medium).to receive(:find_by_id!).with(medium.id).
      and_return(medium)
    expect(Flapjack::Data::Route).to receive(:find_by_ids!).with(route.id).
      and_return([route])

    expect(medium_routes).to receive(:ids).and_return([])
    expect(medium_routes).to receive(:add).with(route)
    expect(medium).to receive(:routes).twice.and_return(medium_routes)

    put "/media/#{medium.id}/links/routes", Flapjack.dump_json(:routes => [route.id]), jsonapi_put_env
    expect(last_response.status).to eq(204)
  end

  it 'deletes a route from a medium' do
    expect(Flapjack::Data::Medium).to receive(:find_by_id!).with(medium.id).
      and_return(medium)

    expect(medium_routes).to receive(:find_by_ids!).with(route.id).
      and_return([route])
    expect(medium_routes).to receive(:delete).with(route)
    expect(medium).to receive(:routes).and_return(medium_routes)

    delete "/media/#{medium.id}/links/routes/#{route.id}"
    expect(last_response.status).to eq(204)
  end

end
