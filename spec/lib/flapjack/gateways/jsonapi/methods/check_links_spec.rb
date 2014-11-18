require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::CheckLinks', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  it 'adds tags to a check'

  it 'lists tags for a check'

  it 'updates tags for a check'

  it 'deletes a tag from a check'

end
