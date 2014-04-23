require 'spec_helper'
require 'flapjack/gateways/api'

describe 'Flapjack::Gateways::API', :sinatra => true, :logger => true do

  def app
    Flapjack::Gateways::API
  end

  let(:redis) { double(::Redis) }

  before(:all) do
    Flapjack::Gateways::API.class_eval {
      set :raise_errors, true
    }
  end

  before(:each) do
    expect(Flapjack::RedisPool).to receive(:new).and_return(redis)
    Flapjack::Gateways::API.instance_variable_set('@config', {})
    Flapjack::Gateways::API.instance_variable_set('@logger', @logger)
    Flapjack::Gateways::API.start
  end

  it "handles a route matching failure" do
    aget "/this/route/doesn't/exist"
    expect(last_response.status).to eq(404)
  end

end
