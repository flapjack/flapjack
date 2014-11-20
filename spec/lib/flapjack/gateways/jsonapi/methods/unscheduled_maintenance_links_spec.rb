require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::UnscheduledMaintenanceLinks', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  it 'sets a check for an unscheduled maintenance period'

  it 'shows the check for an unscheduled maintenance period'

  it 'changes the check for an unscheduled maintenance period'

  it 'clears the check for an unscheduled maintenance period'

end
