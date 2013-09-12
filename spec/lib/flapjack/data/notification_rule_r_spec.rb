require 'spec_helper'
require 'flapjack/data/notification_rule_r'

describe Flapjack::Data::NotificationRuleR, :redis => true do

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
     :warning_media      => Set.new(["email"]),
     :critical_media     => Set.new(["sms", "email"]),
     :warning_blackhole  => false,
     :critical_blackhole => false
    }
  }

  # let(:rule_id) { 'ABC123' }

  let(:timezone) { ActiveSupport::TimeZone.new("Europe/Moscow") }

  def create_notification_rule
    rule = Flapjack::Data::NotificationRuleR.new(rule_data)
    rule.save
    rule
  end

  it "converts time restriction data to an IceCube schedule" do
    sched = Flapjack::Data::NotificationRuleR.
              time_restriction_to_icecube_schedule(weekdays_8_18, timezone)
    sched.should_not be_nil
  end

  it "serializes its contents as JSON"

  it "checks whether entity names match" do
    rule = Flapjack::Data::NotificationRuleR.new(rule_data)

    rule.match_entity?('foo-app-01.example.com').should be_true
    rule.match_entity?('foo-app-02.example.com').should be_false
  end

  it "checks whether entity tags match" do
    rule = Flapjack::Data::NotificationRuleR.new(rule_data)

    rule.match_tags?(['database', 'physical'].to_set).should be_true
    rule.match_tags?(['database', 'physical', 'beetroot'].to_set).should be_true
    rule.match_tags?(['database'].to_set).should be_false
    rule.match_tags?(['virtual'].to_set).should be_false
  end

  it "checks if blackhole settings for a rule match a severity level" do
    rule_data[:warning_blackhole] = true
    rule = Flapjack::Data::NotificationRuleR.new(rule_data)

    rule.blackhole?('warning').should be_true
    rule.blackhole?('critical').should be_false
  end

  it "returns the media settings for a rule's severity level" do
    rule = Flapjack::Data::NotificationRuleR.new(rule_data)

    warning_media = rule.media_for_severity('warning')
    warning_media.should be_a(Set)
    warning_media.to_a.should == ['email']
    critical_media = rule.media_for_severity('critical')
    critical_media.should be_a(Set)
    critical_media.to_a.should =~ ['email', 'sms']
  end

end
