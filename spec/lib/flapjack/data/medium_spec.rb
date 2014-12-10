require 'spec_helper'

require 'flapjack/data/medium'

describe Flapjack::Data::Medium, :redis => true do

  it "requires the interval be set for email" do
    medium = Flapjack::Data::Medium.new(:transport => 'email')
    expect(medium.valid?).to be false
    expect(medium.errors[:interval]).to match_array(["can't be blank", "is not a number"])
  end

  it "requires the interval be nil for pagerduty" do
    medium = Flapjack::Data::Medium.new(:transport => 'pagerduty', :interval => 5)
    expect(medium.valid?).to be false
    expect(medium.errors[:interval]).to match_array(["must be nil"])
  end

end
