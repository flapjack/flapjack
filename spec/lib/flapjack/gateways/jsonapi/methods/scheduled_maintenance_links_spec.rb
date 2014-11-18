require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::ScheduledMaintenanceLinks', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  it 'sets a contact for a scheduled maintenance period'

  it 'shows the contact for a scheduled maintenance period'

  it 'changes the contact for a scheduled maintenance period'

  it 'clears the contact for a scheduled maintenance period'

end
