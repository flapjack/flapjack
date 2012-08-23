require 'spec_helper'
require 'flapjack/models/entity_check'

describe Flapjack::Data::EntityCheck, :redis => true do

  let(:name)  { 'abc-123' }
  let(:check) { 'ping' }

  context "maintenance" do

    it "returns that it is in unscheduled maintenance"

    it "returns that it is not in unscheduled maintenance"

    it "returns that it is in scheduled maintenance"

    it "returns that it is not in scheduled maintenance"

    it "returns a list of scheduled maintenance periods"

    it "creates a scheduled maintenance period"

    it "removes a scheduled maintenance period"

    it "updates scheduled maintenance periods"

  end

  it "creates an event"

  it "creates an acknowledgement"

  it "updates state"

  it "returns its status"

  it "returns its last notifications"

  it "returns a status summary"

end