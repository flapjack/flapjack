require 'spec_helper'
require 'flapjack/data/rule'

describe Flapjack::Data::Rule, :redis => true do

  let(:weekdays_8_18) {
    wd = IceCube::Schedule.new(Time.local(2013,2,1,8,0,0), :duration => 60 * 60 * 10)
    wd.add_recurrence_rule(IceCube::Rule.weekly.day(:monday, :tuesday, :wednesday, :thursday, :friday))
    wd
  }

  let(:seven_fifty_nine)     { Time.local(2013,2,1,7,59,0)  }
  let(:eight_zero_one)       { Time.local(2013,2,1,8,1,0)   }
  let(:seventeen_fifty_nine) { Time.local(2013,2,1,17,59,0) }
  let(:eighteen_zero_one)    { Time.local(2013,2,1,18,1,0)  }

  it 'accepts a valid ical string as a time restriction value' do
    rule_opts = {:enabled => true, :blackhole => false, :strategy => 'global'}

    rule = Flapjack::Data::Rule.new(rule_opts.merge(:time_restriction_ical => weekdays_8_18.to_ical))
    expect(rule.is_occurring_at?(seven_fifty_nine)).to be false
    expect(rule.is_occurring_at?(eight_zero_one)).to be true
    expect(rule.is_occurring_at?(seventeen_fifty_nine)).to be true
    expect(rule.is_occurring_at?(eighteen_zero_one)).to be false
    expect(rule).to be_valid

    rule_2 = Flapjack::Data::Rule.new(rule_opts)
    rule_2.time_restriction = weekdays_8_18
    expect(rule_2.is_occurring_at?(seven_fifty_nine)).to be false
    expect(rule_2.is_occurring_at?(eight_zero_one)).to be true
    expect(rule_2.is_occurring_at?(seventeen_fifty_nine)).to be true
    expect(rule_2.is_occurring_at?(eighteen_zero_one)).to be false
    expect(rule_2).to be_valid
  end

  it 'rejects an invalid ical string as a time restriction value' do
    rule_opts = {:enabled => true, :blackhole => false, :strategy => 'global'}

    rule = Flapjack::Data::Rule.new(rule_opts.merge(:time_restriction_ical => 'HAHAHA'))
    expect(rule.time_restriction).to be_nil
    expect(rule).not_to be_valid
  end
end
