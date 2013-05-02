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
    {:entity_tags        => ["database","physical"],
     :entities           => ["foo-app-01.example.com"],
     :time_restrictions  => [ weekdays_8_18 ],
     :warning_media      => ["email"],
     :critical_media     => ["sms", "email"],
     :warning_blackhole  => false,
     :critical_blackhole => false
    }
  }

  let(:rule_id) { 'ABC123' }

  let(:time_zone) { ActiveSupport::TimeZone.new("Europe/Moscow") }

  let(:existing_rule) {
    Flapjack::Data::NotificationRule.add(rule_data, time_zone, :redis => @redis)
  }

  it "checks that a notification rule exists" do
    Flapjack::Data::NotificationRule.exists_with_id?(existing_rule.id, :redis => @redis).should be_true
    Flapjack::Data::NotificationRule.exists_with_id?('not_there', :redis => @redis).should be_false
  end

  it "returns a notification rule if it exists" do
    rule = Flapjack::Data::NotificationRule.find_by_id(existing_rule.id, :redis => @redis)
    rule.should_not be_nil
  end

  it "does not return a notification rule if it does not exist" do
    rule = Flapjack::Data::NotificationRule.find_by_id('not_there', :redis => @redis)
    rule.should be_nil
  end

  it "updates a notification rule" do
    rule = Flapjack::Data::NotificationRule.find_by_id(existing_rule.id, :redis => @redis)

    expect {
      rule_data[:warning_blackhole] = true
      success = rule.update(rule_data, time_zone)
      success.should be_true
    }.to change { rule.warning_blackhole }.from(false).to(true)
  end

  it "converts time restriction data to an IceCube hash"

  it "generates a JSON string representing its data"

  it "checks whether tag or entity names match"

  it "checks if blackhole settings for a rule match a severity level"

  it "returns the media settings for a rule's severity level"

  context 'validation' do

    it "fails to add a notification rule with invalid data" do
      rule_data[:entities] = []
      rule_data[:entity_tags] = []
      rule = Flapjack::Data::NotificationRule.add(rule_data, time_zone, :redis => @redis)
      rule.should be_nil
    end

    it "fails to update a notification rule with invalid data" do
      rule = Flapjack::Data::NotificationRule.add(rule_data, time_zone, :redis => @redis)
      expect {
        rule_data[:entities] = [57]
        success = rule.update(rule_data, time_zone)
        success.should be_false
      }.not_to change { rule.entities }
    end

  end

end