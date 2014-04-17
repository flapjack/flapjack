require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::MediumMethods', :sinatra => true, :logger => true do

  def app
    Flapjack::Gateways::JSONAPI
  end

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

  after(:each) do
    if last_response.status >= 200 && last_response.status < 300
      expect(last_response.headers.keys).to include('Access-Control-Allow-Methods')
      expect(last_response.headers['Access-Control-Allow-Origin']).to eq("*")
      unless last_response.status == 204
        expect(Oj.load(last_response.body)).to be_a(Enumerable)
        expect(last_response.headers['Content-Type']).to eq(Flapjack::Gateways::JSONAPI::JSONAPI_MEDIA_TYPE)
      end
    end
  end

  it "returns the media of a contact"

  it "returns the specified medium of a contact"

  it "does not return the media of a contact if the media is not present"

  it "creates/updates a medium form a contact"

  it "does not create a medium for a contact that's not present"

  it "does not create a medium for a contact if no address is provided"

  it "creates a medium for a contact even if no interval is provided"

  it "deletes a media of a contact"

  it "does not delete a media of a contact that's not present"

end
