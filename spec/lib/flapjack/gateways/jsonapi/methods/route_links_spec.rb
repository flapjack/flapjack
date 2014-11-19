require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::RouteLinks', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:route)  { double(Flapjack::Data::Route, :id => route_data[:id]) }
  let(:rule)   { double(Flapjack::Data::Rule, :id => rule_data[:id]) }
  let(:medium) { double(Flapjack::Data::Medium, :id => email_data[:id]) }

  let(:route_media)  { double('route_media') }

  it 'sets a rule for a route' do
    expect(Flapjack::Data::Route).to receive(:find_by_ids!).with(route.id).
      and_return([route])
    expect(Flapjack::Data::Rule).to receive(:find_by_ids!).with(rule.id).
      and_return([rule])

    expect(route).to receive(:rule).and_return(nil)
    expect(route).to receive(:rule=).with(rule)

    post "/routes/#{route.id}/links/rule", Flapjack.dump_json(:rule => rule.id), jsonapi_post_env
    expect(last_response.status).to eq(204)
  end

  it 'shows the rule for a route' do
    expect(route).to receive(:rule).and_return(rule)

    expect(Flapjack::Data::Route).to receive(:find_by_ids!).with(route.id).
      and_return([route])

    get "/routes/#{route.id}/links/rule"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to eq(Flapjack.dump_json(:rule => rule.id))
  end

  it 'changes the rule for a route' do
    expect(Flapjack::Data::Route).to receive(:find_by_ids!).with(route.id).
      and_return([route])
    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule.id).
      and_return(rule)

    expect(route).to receive(:rule=).with(rule)

    put "/routes/#{route.id}/links/rule", Flapjack.dump_json(:rule => rule.id), jsonapi_put_env
    expect(last_response.status).to eq(204)
  end

  it 'clears the rule for a route' do
    expect(Flapjack::Data::Route).to receive(:find_by_ids!).with(route.id).
      and_return([route])

    expect(route).to receive(:rule).and_return(rule)
    expect(route).to receive(:rule=).with(nil)

    delete "/routes/#{route.id}/links/rule"
    expect(last_response.status).to eq(204)
  end

  it 'adds a medium to a route' do
    expect(Flapjack::Data::Route).to receive(:find_by_ids!).with(route.id).
      and_return([route])
    expect(Flapjack::Data::Medium).to receive(:find_by_ids!).with(medium.id).
      and_return([medium])

    expect(route_media).to receive(:add).with(medium)
    expect(route).to receive(:media).and_return(route_media)

    post "/routes/#{route.id}/links/media", Flapjack.dump_json(:media => medium.id), jsonapi_post_env
    expect(last_response.status).to eq(204)
  end

  it 'lists media for a route' do
    expect(route_media).to receive(:ids).and_return([medium.id])
    expect(route).to receive(:media).and_return(route_media)

    expect(Flapjack::Data::Route).to receive(:find_by_ids!).with(route.id).
      and_return([route])

    get "/routes/#{route.id}/links/media"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to eq(Flapjack.dump_json(:media => [medium.id]))
  end

  it 'updates media for a route' do
    expect(Flapjack::Data::Route).to receive(:find_by_ids!).with(route.id).
      and_return([route])
    expect(Flapjack::Data::Medium).to receive(:find_by_ids!).with(medium.id).
      and_return([medium])

    expect(route_media).to receive(:ids).and_return([])
    expect(route_media).to receive(:add).with(medium)
    expect(route).to receive(:media).twice.and_return(route_media)

    put "/routes/#{route.id}/links/media", Flapjack.dump_json(:media => [medium.id]), jsonapi_put_env
    expect(last_response.status).to eq(204)
  end

  it 'deletes a medium from a route' do
    expect(Flapjack::Data::Route).to receive(:find_by_ids!).with(route.id).
      and_return([route])

    expect(route_media).to receive(:find_by_ids!).with(medium.id).
      and_return([medium])
    expect(route_media).to receive(:delete).with(medium)
    expect(route).to receive(:media).and_return(route_media)

    delete "/routes/#{route.id}/links/media/#{medium.id}"
    expect(last_response.status).to eq(204)
  end

end
