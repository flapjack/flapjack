require 'spec_helper'

require 'active_support/time_with_zone'
require 'ice_cube'
require 'flapjack/data/contact'
require 'flapjack/data/check'
require 'flapjack/data/notification_rule'

describe Flapjack::Data::Contact, :redis => true do

  let(:notification_rule_data) {
    {:time_restrictions  => [],
    }
  }

  let(:general_notification_rule_data) {
    {:time_restrictions  => [],
   }
  }

  let(:redis) { Flapjack.redis }

  context 'notification rules' do

    it "creates a general notification rule for a pre-existing contact if none exists" do
      Factory.contact(:id => '1', :first_name => 'John', :last_name => 'Smith',
        :email => 'jsmith@example.com')
      contact = Flapjack::Data::Contact.find_by_id('1')

      rules = nil
      expect {
        rules = contact.notification_rules.all
      }.to change { Flapjack::Data::NotificationRule.count }.by(1)
      expect(rules.first.is_specific?).not_to be_truthy
    end

    it "creates a general notification rule for a pre-existing contact if the existing general one was changed" do
      Factory.contact(:id => '1', :first_name => 'John', :last_name => 'Smith',
        :email => 'jsmith@example.com')

      Factory.tag(:id => '55', :name => 'staging')
      tag = Flapjack::Data::Tag.intersect(:name => 'staging').all.first

      contact = Flapjack::Data::Contact.find_by_id('1')
      rules = contact.notification_rules.all
      expect(rules.size).to eq(1)

      rules.first.tags << tag

      rules = contact.notification_rules.all
      expect(rules.size).to eq(2)
      expect(rules.select {|r| r.is_specific? }.size).to eq(1)
    end

  end

  context 'timezone' do

    it "sets a timezone string from a string" do
      Factory.contact(:id => '1', :first_name => 'John', :last_name => 'Smith',
        :email => 'jsmith@example.com')
      contact = Flapjack::Data::Contact.find_by_id('1')
      expect(contact.timezone).to be_nil

      contact.time_zone = 'Australia/Adelaide'
      expect(contact.save).to be_truthy
      expect(contact.timezone).to eq('Australia/Adelaide')
      expect(contact.time_zone).to respond_to(:name)
      expect(contact.time_zone.name).to eq('Australia/Adelaide')
    end

    it "sets a timezone string from a time zone"

    it "clears timezone string when set to nil"

    it "returns a time zone"

  end

end
