require 'spec_helper'
require 'flapjack/data/notification_rule'

describe Flapjack::Data::NotificationRule, :redis => true do

  let(:weekdays_8_18) {
    wd = IceCube::Schedule.new(Time.local(2013,2,1,8,0,0), :duration => 60 * 60 * 10)
    wd.add_recurrence_rule(IceCube::Rule.weekly.day(:monday, :tuesday, :wednesday, :thursday, :friday))
    wd = wd.to_hash
    wd[:start_time] = wd.delete(:start_date)
    wd[:rrules].first[:rule_type] = wd[:rrules].first[:rule_type].sub(/\AIceCube::(\w+)Rule\z/, '\1')
    wd
  }

  let(:rule_data) {
    {:tags               => Set.new(["database","physical"]),
     :entities           => Set.new(["foo-app-01.example.com"]),
     :time_restrictions  => [ weekdays_8_18 ],
    }
  }

  let(:timezone) { ActiveSupport::TimeZone.new("Europe/Moscow") }

  def create_notification_rule
    rule = Flapjack::Data::NotificationRule.new(rule_data)

    rule.save
    rule
  end

  it "converts time restriction data to an IceCube schedule" do
    sched = Flapjack::Data::NotificationRule.
              time_restriction_to_icecube_schedule(weekdays_8_18, timezone)
    sched.should_not be_nil
  end

  it "serializes its contents as JSON"

  it "checks whether entity names match" do
    rule = Flapjack::Data::NotificationRule.new(rule_data)

    rule.match_entity?('foo-app-01.example.com').should be_true
    rule.match_entity?('foo-app-02.example.com').should be_false
  end

  it "checks whether entity tags match" do
    rule = Flapjack::Data::NotificationRule.new(rule_data)

    rule.match_tags?(['database', 'physical'].to_set).should be_true
    rule.match_tags?(['database', 'physical', 'beetroot'].to_set).should be_true
    rule.match_tags?(['database'].to_set).should be_false
    rule.match_tags?(['virtual'].to_set).should be_false
  end

end
