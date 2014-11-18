require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::UnscheduledMaintenanceLinks', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  it 'sets a contact for an unscheduled maintenance period'

  it 'shows the contact for an un scheduled maintenance period'

  it 'changes the contact for an un scheduled maintenance period'

  it 'clears the contact for an un scheduled maintenance period'

end
