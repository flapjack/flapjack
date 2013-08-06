require 'spec_helper'

require 'flapjack/gateways/pagerduty'

describe Flapjack::Gateways::Pagerduty, :logger => true do

  let(:config) { {'queue'    => 'pagerduty_notifications'} }

  let(:time)   { Time.new }

  let(:redis) {  mock('redis') }

  context 'notifications' do

  end

  context 'acknowledgements' do

  end

end
