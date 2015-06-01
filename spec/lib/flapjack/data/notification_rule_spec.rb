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
     :regex_tags         => [],
     :entities           => ["foo-app-01.example.com", "foo-app-10.example.com"],
     :regex_entities     => [],
     :time_restrictions  => [ weekdays_8_18 ],
     :unknown_media      => [],
     :warning_media      => ["email"],
     :critical_media     => ["sms", "email"],
     :unknown_blackhole  => false,
     :warning_blackhole  => false,
     :critical_blackhole => false
    }
  }

  let(:empty_rule_data) {
    {:contact_id         => '23',
     :tags               => [],
     :regex_tags         => [],
     :entities           => [],
     :regex_entities     => [],
     :time_restrictions  => [ weekdays_8_18 ],
     :unknown_media      => [],
     :warning_media      => ["email"],
     :critical_media     => ["sms", "email"],
     :unknown_blackhole  => false,
     :warning_blackhole  => false,
     :critical_blackhole => false
    }
  }

  let(:regex_rule_data) {
    {:contact_id         => '23',
     :tags               => [],
     :regex_tags         => ["^data.*$","^(physical|bare_metal)$"],
     :entities           => [],
     :regex_entities     => ['^foo-\S{3}-\d{2}.example.com$','.*abc.*'],
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
    Flapjack::Data::NotificationRule.add(rule_data, :redis => @redis)
  }

  let(:existing_empty_rule) {
    Flapjack::Data::NotificationRule.add(empty_rule_data, :redis => @redis)
  }

  let(:existing_regex_rule) {
    Flapjack::Data::NotificationRule.add(regex_rule_data, :redis => @redis)
  }

  it "checks that a notification rule exists" do
    expect(Flapjack::Data::NotificationRule.exists_with_id?(existing_rule.id, :redis => @redis)).to be true
    expect(Flapjack::Data::NotificationRule.exists_with_id?('not_there', :redis => @redis)).to be false
  end

  it "returns a notification rule if it exists" do
    rule = Flapjack::Data::NotificationRule.find_by_id(existing_rule.id, :redis => @redis)
    expect(rule).not_to be_nil
  end

  it "does not return a notification rule if it does not exist" do
    rule = Flapjack::Data::NotificationRule.find_by_id('not_there', :redis => @redis)
    expect(rule).to be_nil
  end

  it "updates a notification rule" do
    rule = existing_rule

    expect {
      expect {
        errors = rule.update(:warning_blackhole => true)
        expect(errors).to be_nil
      }.to change { rule.warning_blackhole }.from(false).to(true)
    }.not_to change { rule.contact_id }
  end

  it "converts time restriction data to an IceCube schedule" do
    sched = Flapjack::Data::NotificationRule.
              time_restriction_to_icecube_schedule(weekdays_8_18, timezone)
    expect(sched).not_to be_nil
  end

  it "generates a JSON string representing its data" do
    rule = existing_rule
    # bit of extra hackery for the ID values
    munged = {:id => rule.id}.merge(rule_data)
    munged[:links] = {:contacts => [munged.delete(:contact_id)]}
    expect(rule.to_jsonapi).to eq(Flapjack.dump_json(munged))
  end

  it "checks whether entity names match" do
    rule = existing_rule

    expect(rule.match_entity?('foo-app-01.example.com')).to be true
    expect(rule.match_entity?('foo-app-10.example.com')).to be true
    expect(rule.match_entity?('foo-app-02.example.com')).to be false

    expect(existing_empty_rule.match_entity?('anything.example.com')).to be true
  end

  it "checks whether entity names match a regex" do
    rule = existing_regex_rule

    expect(rule.match_regex_entities?('foo-abc-01.example.com')).to be true
    expect(rule.match_regex_entities?('foo-abc-99.example.com')).to be true
    expect(rule.match_regex_entities?('foo-app-01.example.com')).to be false # does not match second regexp_entities
    expect(rule.match_regex_entities?('foo-abc.example.com')).to be false
    expect(rule.match_regex_entities?('bar-abc-01.example.com')).to be false

    expect(existing_empty_rule.match_regex_entities?('anything.example.com')).to be true
  end

  it "checks whether event tags match" do
    rule = existing_rule

    expect(rule.match_tags?(['database', 'physical'].to_set)).to be true
    expect(rule.match_tags?(['database', 'physical', 'beetroot'].to_set)).to be true
    expect(rule.match_tags?(['database'].to_set)).to be false
    expect(rule.match_tags?(['virtual'].to_set)).to be false
    expect(rule.match_tags?([].to_set)).to be false

    expect(existing_empty_rule.match_regex_entities?(['virtual'].to_set)).to be true
  end

  it "checks whether event tags match a regex" do
    rule = existing_regex_rule

    expect(rule.match_regex_tags?(['database', 'physical'].to_set)).to be true
    expect(rule.match_regex_tags?(['database', 'physical', 'beetroot'].to_set)).to be true
    expect(rule.match_regex_tags?(['database'].to_set)).to be false
    expect(rule.match_regex_tags?(['database.physical'].to_set)).to be false # does not match second regex_tags
    expect(rule.match_regex_tags?(['data1', 'data2'].to_set)).to be false # does not match second regex_tags
    expect(rule.match_regex_tags?(['virtual'].to_set)).to be false

    expect(existing_empty_rule.match_regex_entities?(['virtual'].to_set)).to be true
  end

  it "checks if blackhole settings for a rule match a severity level" do
    rule_data[:warning_blackhole] = true
    rule = Flapjack::Data::NotificationRule.add(rule_data, :redis => @redis)

    expect(rule.blackhole?('warning')).to be true
    expect(rule.blackhole?('critical')).to be false
  end

  it "returns the media settings for a rule's severity level" do
    rule = existing_rule
    expect(rule.media_for_severity('warning')).to eq(['email'])
    expect(rule.media_for_severity('critical')).to match_array(['email', 'sms'])
  end

  context 'validation' do

    it "fails to add a notification rule with invalid data" do
      rule_data[:entities] = [1, {}]
      rule_or_errors = Flapjack::Data::NotificationRule.add(rule_data, :redis => @redis)
      expect(rule_or_errors).not_to be_nil
      expect(rule_or_errors).to be_an(Array)
      expect(rule_or_errors.size).to eq(1)
      expect(rule_or_errors).to eq(["Rule entities must be a list of strings"])
    end

    it "fails to update a notification rule with invalid data" do
      rule = Flapjack::Data::NotificationRule.add(rule_data, :redis => @redis)
      expect {
        rule_data[:entities] = [57]
        errors = rule.update(rule_data)
        expect(errors).not_to be_nil
        expect(errors.size).to eq(1)
        expect(errors).to eq(["Rule entities must be a list of strings"])
      }.not_to change { rule.entities }
    end

    # https://github.com/flapjack/flapjack/issues/549
    it "fails to add a notification rule with invalid data" do
      rule_data[:time_restrictions] = [
        {
          "start_time" => "2014-06-22 00:00:00",
          "end_time" => "2015-01-01 00:00:00",
          "rrules" => [
            {
              "validations" => {
                "day" => [1,2,3,4,5,6,7]
              },
              "rule_type" => "Weekly",
              "interval" => 1,
              "week_start" => 0
            }
          ],
          "exrules" => [],
          "rtimes" => [],
          "extimes" => []
        }
      ]
      rule_or_errors = Flapjack::Data::NotificationRule.add(rule_data, :redis => @redis)
      expect(rule_or_errors).not_to be_nil
      expect(rule_or_errors).to be_an(Array)
      expect(rule_or_errors.size).to eq(1)
      expect(rule_or_errors).to eq(["Rule time restrictions are invalid"])
    end

  end

end
