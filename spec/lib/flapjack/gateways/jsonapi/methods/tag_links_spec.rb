require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::TagLinks', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  it 'adds a check to a tag'

  it 'lists checks for a tag'

  it 'updates checks for a tag'

  it 'deletes a check from a tag'

  it 'adds a rule to a tag'

  it 'lists rules for a tag'

  it 'updates rules for a tag'

  it 'deletes rules from a tag'

end
