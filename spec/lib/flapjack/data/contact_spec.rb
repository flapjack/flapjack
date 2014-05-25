require 'spec_helper'

require 'active_support/time_with_zone'
require 'ice_cube'
require 'flapjack/data/contact'
require 'flapjack/data/check'
require 'flapjack/data/notification_rule'

describe Flapjack::Data::Contact, :redis => true do

  let(:notification_rule_data) {
    {:tags               => Set.new(["database","physical"]),
     :entities           => Set.new(["foo-app-01.example.com"]),
     :time_restrictions  => [],
    }
  }

  let(:general_notification_rule_data) {
    {:entities           => Set.new,
     :tags               => Set.new,
     :time_restrictions  => [],
   }
  }

  let(:redis) { Flapjack.redis }

  it "returns a contact's name" do
    Factory.contact(:id => '1', :first_name => 'John', :last_name => 'Smith',
      :email => 'jsmith@example.com') # raw redis
    contact = Flapjack::Data::Contact.find_by_id('1')

    expect(contact).not_to be_nil
    expect(contact.name).to eq('John Smith')
  end

  it "returns a list of entities and their checks for a contact"

  # it "returns a list of entities and their checks for a contact" do
  #   entity_name = 'abc-123'

  #   Flapjack::Data::Entity.add({'id'   => '5000',
  #                               'name' => entity_name,
  #                               'contacts' => ['362']})

  #   ec = Flapjack::Data::EntityCheck.for_entity_name(entity_name, 'PING')
  #   t = Time.now.to_i
  #   ec.update_state('ok', :timestamp => t, :summary => 'a')
  #   ec.last_update = t

  #   contact = Flapjack::Data::Contact.find_by_id('362')
  #   eandcs = contact.entities(:checks => true)
  #   eandcs.should_not be_nil
  #   eandcs.should be_an(Array)
  #   eandcs.should have(1).entity_and_checks

  #   eandc = eandcs.first
  #   eandc.should be_a(Hash)

  #   entity = eandc[:entity]
  #   entity.name.should == entity_name
  #   checks = eandc[:checks]
  #   checks.should be_a(Set)
  #   checks.should have(1).check
  #   checks.should include('PING')
  # end

  it "deletes linked entities, tags and notification rules"

  # it "deletes linked entities, checks, tags and notification rules" do
  #   contact = Flapjack::Data::Contact.find_by_id('362')
  #   contact.add_tags('admin')

  #   entity_name = 'abc-123'

  #   entity = Flapjack::Data::Entity.add({'id'   => '5000',
  #                                        'name' => entity_name,
  #                                        'contacts' => ['362']})

  #   expect {
  #     expect {
  #       expect {
  #         contact.delete!
  #       }.to change { Flapjack::Data::Contact.all.size }.by(-1)
  #     }.to change { Flapjack.redis.smembers('contact_tag:admin').size }.by(-1)
  #   }.to change { entity.contacts.size }.by(-1)
  # end

  context 'notification rules' do

    it "creates a general notification rule for a pre-existing contact if none exists" do
      Factory.contact(:id => '1', :first_name => 'John', :last_name => 'Smith',
        :email => 'jsmith@example.com') # raw redis
      contact = Flapjack::Data::Contact.find_by_id('1')

      rules = nil
      expect {
        rules = contact.notification_rules.all
      }.to change { Flapjack::Data::NotificationRule.count }.by(1)
      expect(rules.first.is_specific?).not_to be_truthy
    end

    it "creates a general notification rule for a pre-existing contact if the existing general one was changed" do
      Factory.contact(:id => '1', :first_name => 'John', :last_name => 'Smith',
        :email => 'jsmith@example.com') # raw redis
      contact = Flapjack::Data::Contact.find_by_id('1')
      rules = contact.notification_rules.all
      expect(rules.size).to eq(1)

      rule = rules.first
      rule.tags = Set.new(['staging'])
      rule.save

      rules = contact.notification_rules.all
      expect(rules.size).to eq(2)
      expect(rules.select {|r| r.is_specific? }.size).to eq(1)
    end

  end

  context 'timezone' do

    it "sets a timezone string from a string" do
      Factory.contact(:id => '1', :first_name => 'John', :last_name => 'Smith',
        :email => 'jsmith@example.com') # raw redis
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
