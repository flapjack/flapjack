require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::ContactLinks', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  it 'adds media to a contact'

  it 'lists media for a contact'

  it 'updates media for a contact'

  it 'deletes media from a contact'

  it 'adds a rule to a contact'

  it 'lists rules for a contact'

  it 'updates rules for a contact'

  it 'deletes a rule from a contact'

end
