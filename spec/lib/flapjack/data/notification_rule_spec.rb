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
    {:contact_id         => '23',
     :tags               => ["database","physical"],
     :entities           => ["foo-app-01.example.com"],
     :time_restrictions  => [ weekdays_8_18 ],
     :unknown_media      => [],
     :warning_media      => ["email"],
     :critical_media     => ["sms", "email"],
     :unknown_blackhole  => false,
     :warning_blackhole  => false,
     :critical_blackhole => false
    }
  }

  let(:rule_id) { 'ABC123' }

  let(:timezone) { ActiveSupport::TimeZone.new("Europe/Moscow") }

  let(:existing_rule) {
    Flapjack::Data::NotificationRule.add(rule_data)
  }

  it "checks that a notification rule exists" do
    Flapjack::Data::NotificationRule.exists_with_id?(existing_rule.id).should be_true
    Flapjack::Data::NotificationRule.exists_with_id?('not_there').should be_false
  end

  it "returns a notification rule if it exists" do
    rule = Flapjack::Data::NotificationRule.find_by_id(existing_rule.id)
    rule.should_not be_nil
  end

  it "does not return a notification rule if it does not exist" do
    rule = Flapjack::Data::NotificationRule.find_by_id('not_there')
    rule.should be_nil
  end

  it "updates a notification rule" do
    rule = existing_rule

    expect {
      rule_data[:warning_blackhole] = true
      errors = rule.update(rule_data)
      errors.should be_nil
    }.to change { rule.warning_blackhole }.from(false).to(true)
  end

  it "converts time restriction data to an IceCube schedule" do
    sched = Flapjack::Data::NotificationRule.
              time_restriction_to_icecube_schedule(weekdays_8_18, timezone)
    sched.should_not be_nil
  end

  it "generates a JSON string representing its data" do
    rule = existing_rule
    # bit of extra hackery for the inserted ID values
    rule.to_json.should == {:id => rule.id}.merge(rule_data).to_json
  end

  it "checks whether entity names match" do
    rule = existing_rule

    rule.match_entity?('foo-app-01.example.com').should be_true
    rule.match_entity?('foo-app-02.example.com').should be_false
  end

  it "checks whether entity tags match" do
    rule = existing_rule

    rule.match_tags?(['database', 'physical'].to_set).should be_true
    rule.match_tags?(['database', 'physical', 'beetroot'].to_set).should be_true
    rule.match_tags?(['database'].to_set).should be_false
    rule.match_tags?(['virtual'].to_set).should be_false
  end

  it "checks if blackhole settings for a rule match a severity level" do
    rule_data[:warning_blackhole] = true
    rule = Flapjack::Data::NotificationRule.add(rule_data)

    rule.blackhole?('warning').should be_true
    rule.blackhole?('critical').should be_false
  end

  it "returns the media settings for a rule's severity level" do
    rule = existing_rule
    rule.media_for_severity('warning').should == ['email']
    rule.media_for_severity('critical').should =~ ['email', 'sms']
  end

  context 'validation' do

    it "fails to add a notification rule with invalid data" do
      rule_data[:entities] = [1, {}]
      rule_or_errors = Flapjack::Data::NotificationRule.add(rule_data)
      rule_or_errors.should_not be_nil
      rule_or_errors.should be_an(Array)
      rule_or_errors.should have(1).error
      rule_or_errors.should == ["Rule entities must be a list of strings"]
    end

    it "fails to update a notification rule with invalid data" do
      rule = Flapjack::Data::NotificationRule.add(rule_data)
      expect {
        rule_data[:entities] = [57]
        errors = rule.update(rule_data)
        errors.should_not be_nil
        errors.should have(1).error
        errors.should == ["Rule entities must be a list of strings"]
      }.not_to change { rule.entities }
    end

  end

end
