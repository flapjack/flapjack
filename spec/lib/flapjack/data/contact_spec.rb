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
     :warning_media      => Set.new(["email"]),
     :critical_media     => Set.new(["sms", "email"]),
     :warning_blackhole  => false,
     :critical_blackhole => false
    }
  }

  let(:general_notification_rule_data) {
    {:entities           => Set.new,
     :tags               => Set.new,
     :time_restrictions  => [],
     :warning_media      => Set.new(['email', 'sms', 'jabber', 'pagerduty']),
     :critical_media     => Set.new(['email', 'sms', 'jabber', 'pagerduty']),
     :warning_blackhole  => false,
     :critical_blackhole => false}
  }

  let(:redis) { Flapjack.redis }

  def create_contact
    redis.hmset('contact:1:attrs', {'first_name' => 'John',
      'last_name' => 'Smith', 'email' => 'jsmith@example.com'}.flatten)
    redis.sadd('contact::ids', '1')
  end

  it "returns a contact's name" do
    create_contact # raw redis
    contact = Flapjack::Data::Contact.find_by_id('1')

    contact.should_not be_nil
    contact.name.should == 'John Smith'
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
      create_contact # raw redis
      contact = Flapjack::Data::Contact.find_by_id('1')

      rules = nil
      expect {
        rules = contact.notification_rules.all
      }.to change { Flapjack::Data::NotificationRule.count }.by(1)
      rules.first.is_specific?.should_not be_true
    end

    it "creates a general notification rule for a pre-existing contact if the existing general one was changed" do
      create_contact # raw redis
      contact = Flapjack::Data::Contact.find_by_id('1')
      rules = contact.notification_rules.all
      rules.should have(1).notification_rule

      rule = rules.first
      rule.tags = Set.new(['staging'])
      rule.save

      rules = contact.notification_rules.all
      rules.should have(2).notification_rules
      rules.select {|r| r.is_specific? }.should have(1).rule
    end

  end

  context 'timezone' do

    it "sets a timezone string from a string" do
      create_contact # raw redis
      contact = Flapjack::Data::Contact.find_by_id('1')
      contact.timezone.should be_nil

      contact.time_zone = 'Australia/Adelaide'
      contact.save.should be_true
      contact.timezone.should == 'Australia/Adelaide'
      contact.time_zone.should respond_to(:name)
      contact.time_zone.name.should == 'Australia/Adelaide'
    end

    it "sets a timezone string from a time zone"

    it "clears timezone string when set to nil"

    it "returns a time zone"

  end

  it "serializes its contents as JSON" do
    create_contact # raw redis
    contact = Flapjack::Data::Contact.find_by_id('1')

    contact.should respond_to(:to_json)
    contact_json = contact.to_json(:root => false,
      :only => [:id, :first_name, :last_name, :email, :tags])
    contact_json.should == {"email"      => "jsmith@example.com",
                            "first_name" => "John",
                            "id"         => '1',
                            "last_name"  => "Smith",
                            "tags"       => [] }.to_json
  end

  it "clears expired notification blocks" do
    t = Time.now

    create_contact # raw redis
    contact = Flapjack::Data::Contact.find_by_id('1')

    old_notification_block = Flapjack::Data::NotificationBlock.new(
      :expire_at => t.to_i - (60 * 60), :media_type => 'sms')
    old_notification_block.save.should be_true

    new_notification_block = Flapjack::Data::NotificationBlock.new(
      :expire_at => t.to_i + (60 * 60), :media_type => 'sms')
    new_notification_block.save.should be_true

    contact.notification_blocks << old_notification_block <<
      new_notification_block

    contact.notification_blocks.count.should == 2
    contact.expire_notification_blocks
    contact.notification_blocks.count.should == 1
    contact.notification_blocks.first.id.should == new_notification_block.id
  end

end
