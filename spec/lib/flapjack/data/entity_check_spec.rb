require 'spec_helper'
require 'flapjack/data/entity_check'

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

  it "returns its state" do
    # ec = EntityCheck.new(:entity_name => , :check => 'ping')


  end

  it "updates state"

  it "returns that it has failed"

  it "returns that it has not failed"

  it "returns a status hash"

  it "returns its last notifications"

  it "returns a status summary"

  it "returns duration of current failure"

  it "returns time since last problem alert"

  it "returns time since last alert about current problem"

end