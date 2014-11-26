require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::Routes', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:route)   { double(Flapjack::Data::Route, :id => route_data[:id]) }
  let(:route_2) { double(Flapjack::Data::Route, :id => route_2_data[:id]) }

  let(:rule)    { double(Flapjack::Data::Rule, :id => rule_data[:id]) }

  it "creates a route" do
    expect(Flapjack::Data::Route).to receive(:lock).with(Flapjack::Data::Rule,
      Flapjack::Data::Medium).and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    full_ids = double('full_ids')
    expect(full_ids).to receive(:associated_ids_for).with(:rule).and_return({route.id => nil})
    expect(full_ids).to receive(:associated_ids_for).with(:media).and_return({route.id => []})
    expect(Flapjack::Data::Route).to receive(:intersect).
      with(:id => [route_data[:id]]).exactly(3).times.and_return(empty_ids, full_ids, full_ids)

    expect(route).to receive(:invalid?).and_return(false)
    expect(route).to receive(:save).and_return(true)
    expect(Flapjack::Data::Route).to receive(:new).with(route_data).
      and_return(route)

    expect(route).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(route_data)

    post "/routes", Flapjack.dump_json(:routes => route_data), jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json(:routes => route_data.merge(:links => {
      :rule => nil,
      :media => []
    })))
  end

  it "does not create a route if the data is improperly formatted" do
    expect(Flapjack::Data::Route).to receive(:lock).with(Flapjack::Data::Rule,
      Flapjack::Data::Medium).and_yield
    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Route).to receive(:intersect).
      with(:id => [route_data[:id]]).and_return(empty_ids)

    errors = double('errors', :full_messages => ['err'])
    expect(route).to receive(:errors).and_return(errors)

    expect(route).to receive(:invalid?).and_return(true)
    expect(route).not_to receive(:save)
    expect(Flapjack::Data::Route).to receive(:new).with(route_data).
      and_return(route)

    post "/routes", Flapjack.dump_json(:routes => route_data), jsonapi_post_env
    expect(last_response.status).to eq(403)
  end

  it "creates a route linked to a rule" do
    expect(Flapjack::Data::Route).to receive(:lock).
      with(Flapjack::Data::Rule, Flapjack::Data::Medium).and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    full_ids = double('full_ids')
    expect(full_ids).to receive(:associated_ids_for).with(:rule).and_return({route.id => rule.id})
    expect(full_ids).to receive(:associated_ids_for).with(:media).and_return({route.id => []})
    expect(Flapjack::Data::Route).to receive(:intersect).
      with(:id => [route_data[:id]]).exactly(3).times.and_return(empty_ids, full_ids, full_ids)

    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule_data[:id]).
      and_return(rule)

    expect(route).to receive(:invalid?).and_return(false)
    expect(route).to receive(:save).and_return(true)
    expect(route).to receive(:rule=).with(rule)
    expect(Flapjack::Data::Route).to receive(:new).with(route_data).
      and_return(route)

    expect(route).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(route_data)

    post "/routes", Flapjack.dump_json(:routes => route_data.merge(:links => {:rule => rule.id})), jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json(:links => {
        'routes.rule' => 'http://example.org/rules/{routes.rule}',
      },
      :routes => route_data.merge(:links => {
        :rule => rule.id,
        :media => []
      }
    )))
  end

  it "does not create a route with a linked rule if the rule doesn't exist" do
    expect(Flapjack::Data::Route).to receive(:lock).
      with(Flapjack::Data::Rule, Flapjack::Data::Medium).and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Route).to receive(:intersect).
      with(:id => [route_data[:id]]).and_return(empty_ids)

    route_with_rule_data = route_data.merge(:links => {
      :rule => rule_data[:id]
    })

    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule_data[:id]).
      and_raise(Sandstorm::Records::Errors::RecordNotFound.new(Flapjack::Data::Rule, rule_data[:id]))

    expect(route).to receive(:invalid?).and_return(false)
    expect(route).not_to receive(:save)
    expect(route).not_to receive(:rule=).with(rule)
    expect(Flapjack::Data::Route).to receive(:new).with(route_data).
      and_return(route)

    expect(Flapjack::Data::Route).not_to receive(:as_jsonapi)

    post "/routes", Flapjack.dump_json(:routes => route_with_rule_data), jsonapi_post_env
    expect(last_response.status).to eq(404)
  end

  it "gets all routes" do
    meta = {
      :pagination => {
        :page        => 1,
        :per_page    => 20,
        :total_pages => 1,
        :total_count => 1
      }
    }

    expect(Flapjack::Data::Route).to receive(:count).and_return(1)

    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).
      and_return([route])
    expect(Flapjack::Data::Route).to receive(:sort).
      with(:id).and_return(sorted)

    full_ids = double('full_ids')
    expect(full_ids).to receive(:associated_ids_for).with(:rule).and_return({route.id => nil})
    expect(full_ids).to receive(:associated_ids_for).with(:media).and_return({route.id => []})
    expect(Flapjack::Data::Route).to receive(:intersect).
      with(:id => [route.id]).twice.and_return(full_ids)

    expect(route).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(route_data)

    get '/routes'
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:routes => [route_data.merge(:links => {
      :rule => nil,
      :media => []
    })], :meta => meta))
  end

  it "gets a single route" do
    expect(Flapjack::Data::Route).to receive(:find_by_id!).
      with(route.id).and_return(route)

    full_ids = double('full_ids')
    expect(full_ids).to receive(:associated_ids_for).with(:rule).and_return({route.id => nil})
    expect(full_ids).to receive(:associated_ids_for).with(:media).and_return({route.id => []})
    expect(Flapjack::Data::Route).to receive(:intersect).
      with(:id => [route.id]).twice.and_return(full_ids)

    expect(route).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(route_data)

    get "/routes/#{route.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:routes => route_data.merge(:links => {
      :rule => nil,
      :media => []
    })))
  end

  it "does not get a route that does not exist" do
    expect(Flapjack::Data::Route).to receive(:find_by_id!).
      with(route.id).
      and_raise(Sandstorm::Records::Errors::RecordNotFound.new(Flapjack::Data::Route, route.id))

    get "/routes/#{route.id}"
    expect(last_response).to be_not_found
  end

  it "sets a rule for a route" do
    expect(Flapjack::Data::Route).to receive(:find_by_ids!).
      with(route.id).and_return([route])

    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule_data[:id]).
      and_return(rule)

    expect(route).to receive(:invalid?).and_return(false)
    expect(route).to receive(:save).and_return(true)

    expect(route).to receive(:rule=).with(rule)

    put "/routes/#{route.id}",
      Flapjack.dump_json(:routes =>
        {:id => route.id, :links => {:rule => rule.id}}
      ),
      jsonapi_put_env
    expect(last_response.status).to eq(204)
  end

  it "sets a rule for multiple routes" do
    expect(Flapjack::Data::Route).to receive(:find_by_ids!).
      with(route.id, route_2.id).and_return([route, route_2])

    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule_data[:id]).
      twice.and_return(rule)

    expect(route).to receive(:invalid?).and_return(false)
    expect(route).to receive(:save).and_return(true)

    expect(route_2).to receive(:invalid?).and_return(false)
    expect(route_2).to receive(:save).and_return(true)

    expect(route).to receive(:rule=).with(rule)
    expect(route_2).to receive(:rule=).with(rule)

    put "/routes/#{route.id},#{route_2.id}",
      Flapjack.dump_json(:routes => [
        {:id => route.id, :links => {:rule => rule.id}},
        {:id => route_2.id, :links => {:rule => rule.id}}
      ]),
      jsonapi_put_env
    expect(last_response.status).to eq(204)
  end

  it "does not set a rule for a route that does not exist" do
    expect(Flapjack::Data::Route).to receive(:find_by_ids!).
      with(route.id).
      and_raise(Sandstorm::Records::Errors::RecordsNotFound.new(Flapjack::Data::Route, [route.id]))

    put "/routes/#{route.id}",
      Flapjack.dump_json(:routes =>
        {:id => route.id, :links => {:rule => rule.id}}
      ),
      jsonapi_put_env
    expect(last_response.status).to eq(404)
  end

  it "deletes a route" do
    routes = double('routes')
    expect(routes).to receive(:ids).and_return([route.id])
    expect(routes).to receive(:destroy_all)
    expect(Flapjack::Data::Route).to receive(:intersect).
      with(:id => [route.id]).and_return(routes)

    delete "/routes/#{route.id}"
    expect(last_response.status).to eq(204)
  end

  it "deletes multiple routes" do
    routes = double('routes')
    expect(routes).to receive(:ids).
      and_return([route.id, route_2.id])
    expect(routes).to receive(:destroy_all)
    expect(Flapjack::Data::Route).to receive(:intersect).
      with(:id => [route.id, route_2.id]).
      and_return(routes)

    delete "/routes/#{route.id},#{route_2.id}"
    expect(last_response.status).to eq(204)
  end

  it "does not delete a route that does not exist" do
    routes = double('routes')
    expect(routes).to receive(:ids).and_return([])
    expect(routes).not_to receive(:destroy_all)
    expect(Flapjack::Data::Route).to receive(:intersect).
      with(:id => [route.id]).and_return(routes)

    delete "/routes/#{route.id}"
    expect(last_response).to be_not_found
  end

end
