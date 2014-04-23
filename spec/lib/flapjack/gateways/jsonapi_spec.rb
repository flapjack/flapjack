require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI', :sinatra => true, :logger => true do

  def app
    Flapjack::Gateways::JSONAPI
  end

  let(:redis) { double(::Redis) }

  let(:jsonapi_env) {
    {'CONTENT_TYPE' => Flapjack::Gateways::JSONAPI::JSONAPI_MEDIA_TYPE,
     'HTTP_ACCEPT'  => 'application/json; q=0.8, application/vnd.api+json'}
  }

  before(:all) do
    Flapjack::Gateways::JSONAPI.class_eval {
      set :raise_errors, true
    }
  end

  before(:each) do
    expect(Flapjack::RedisPool).to receive(:new).and_return(redis)
    Flapjack::Gateways::JSONAPI.instance_variable_set('@config', {})
    Flapjack::Gateways::JSONAPI.instance_variable_set('@logger', @logger)
    Flapjack::Gateways::JSONAPI.start
  end

  it "handles a route matching failure" do
    aget "/this/route/doesn't/exist", {}, jsonapi_env
    expect(last_response.status).to eq(404)
  end

  it "rejects a POST request with invalid content type"

  it "rejects a PATCH request with invalid content type"

end
