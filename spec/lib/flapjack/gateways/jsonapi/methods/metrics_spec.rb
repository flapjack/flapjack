require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::Metrics', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

end
