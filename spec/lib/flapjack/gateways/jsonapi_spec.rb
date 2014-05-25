require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI', :sinatra => true, :logger => true do

  include_context "jsonapi"

  it "handles a route matching failure" do
    get "/this/route/doesn't/exist"
    expect(last_response.status).to eq(404)
  end

  it "rejects a POST request with invalid content type"

  it "rejects a PATCH request with invalid content type"

end
