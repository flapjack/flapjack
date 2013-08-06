require 'spec_helper'

require 'active_support/time_with_zone'
require 'ice_cube'

require 'flapjack/data/contact'
require 'flapjack/data/entity_check'
require 'flapjack/data/notification_rule'
require 'flapjack/data/tag_set'

describe Flapjack::Data::Contact, :redis => true do

  let(:notification_rule_data) {
    {:tags               => ["database","physical"],
     :entities           => ["foo-app-01.example.com"],
     :time_restrictions  => [],
     :warning_media      => ["email"],
     :critical_media     => ["sms", "email"],
     :warning_blackhole  => false,
     :critical_blackhole => false
    }
  }

  let(:general_notification_rule_data) {
    {:entities           => [],
     :tags               => Flapjack::Data::TagSet.new([]),
     :time_restrictions  => [],
     :warning_media      => ['email', 'sms', 'jabber', 'pagerduty'],
     :critical_media     => ['email', 'sms', 'jabber', 'pagerduty'],
     :warning_blackhole  => false,
     :critical_blackhole => false}
  }

  before(:each) do
    Flapjack::Data::Contact.add({'id'         => '362',
                                 'first_name' => 'John',
                                 'last_name'  => 'Johnson',
                                 'email'      => 'johnj@example.com',
                                 'media' => {
                                    'pagerduty' => {
                                      'service_key' => '123456789012345678901234',
                                      'subdomain'   => 'flpjck',
                                      'username'    => 'flapjack',
                                      'password'    => 'very_secure'
                                    }
                                  }},
                                 :redis       => @redis)

    Flapjack::Data::Contact.add({'id'         => '363',
                                 'first_name' => 'Jane',
                                 'last_name'  => 'Janeley',
                                 'email'      => 'janej@example.com',
                                 'media'      => {
                                    'email' => {
                                      'address'  => 'janej@example.com',
                                      'interval' => 60
                                      }
                                  }},
                                 :redis       => @redis)
  end

  it "returns a list of all contacts" do
    contacts = Flapjack::Data::Contact.all(:redis => @redis)
    contacts.should_not be_nil
    contacts.should be_an(Array)
    contacts.should have(2).contacts
    contacts[0].name.should == 'Jane Janeley'
    contacts[1].name.should == 'John Johnson'
  end

  it "finds a contact by id" do
    contact = Flapjack::Data::Contact.find_by_id('362', :redis => @redis)
    contact.should_not be_nil
    contact.name.should == "John Johnson"
  end

  it "adds a contact with the same id as an existing one, clears notification rules" do
    contact = Flapjack::Data::Contact.find_by_id('363', :redis => @redis)
    contact.should_not be_nil

    contact.add_notification_rule(notification_rule_data)

    nr = contact.notification_rules
    nr.should_not be_nil
    nr.should have(2).notification_rules

    Flapjack::Data::Contact.add({'id'         => '363',
                                 'first_name' => 'Smithy',
                                 'last_name'  => 'Smith',
                                 'email'      => 'smithys@example.com'},
                                 :redis       => @redis)

    contact = Flapjack::Data::Contact.find_by_id('363', :redis => @redis)
    contact.should_not be_nil
    contact.name.should == 'Smithy Smith'
    rules = contact.notification_rules
    rules.should have(1).notification_rule
    nr.map(&:id).should_not include(rules.first.id)
  end

  it "updates a contact and clears their media settings" do
    contact = Flapjack::Data::Contact.find_by_id('363', :redis => @redis)

    contact.update('media' => {})
    contact.media.should be_empty
  end

  it "updates a contact, does not clear notification rules" do
    contact = Flapjack::Data::Contact.find_by_id('363', :redis => @redis)
    contact.should_not be_nil

    contact.add_notification_rule(notification_rule_data)

    nr1 = contact.notification_rules
    nr1.should_not be_nil
    nr1.should have(2).notification_rules

    contact.update('first_name' => 'John',
                   'last_name'  => 'Smith',
                   'email'      => 'johns@example.com')
    contact.name.should == 'John Smith'

    nr2 = contact.notification_rules
    nr2.should_not be_nil
    nr2.should have(2).notification_rules
    nr1.map(&:id).should == nr2.map(&:id)
  end

  it "adds a notification rule for a contact" do
    contact = Flapjack::Data::Contact.find_by_id('363', :redis => @redis)
    contact.should_not be_nil

    expect {
      contact.add_notification_rule(notification_rule_data)
    }.to change { contact.notification_rules.size }.from(1).to(2)
  end

  it "removes a notification rule from a contact" do
    contact = Flapjack::Data::Contact.find_by_id('363', :redis => @redis)
    contact.should_not be_nil

    rule = contact.add_notification_rule(notification_rule_data)

    expect {
      contact.delete_notification_rule(rule)
    }.to change { contact.notification_rules.size }.from(2).to(1)
  end

  it "creates a general notification rule for a pre-existing contact if none exists" do
    contact = Flapjack::Data::Contact.find_by_id('363', :redis => @redis)

    @redis.smembers("contact_notification_rules:363").each do |rule_id|
      @redis.srem("contact_notification_rules:363", rule_id)
    end
    @redis.smembers("contact_notification_rules:363").should be_empty

    rules = contact.notification_rules
    rules.should have(1).rule
    rule = rules.first
    [:entities, :tags, :time_restrictions,
     :warning_media, :critical_media,
     :warning_blackhole, :critical_blackhole].each do |k|
      rule.send(k).should == general_notification_rule_data[k]
    end
  end

  it "creates a general notification rule for a pre-existing contact if the existing general one was changed" do
    contact = Flapjack::Data::Contact.find_by_id('363', :redis => @redis)
    rules = contact.notification_rules
    rules.should have(1).notification_rule
    rule = rules.first

    rule.update(notification_rule_data)

    rules = contact.notification_rules
    rules.should have(2).notification_rules
    rules.select {|r| r.is_specific? }.should have(1).rule
  end

  it "deletes a contact by id, including linked entities, checks, tags and notification rules" do
    contact = Flapjack::Data::Contact.find_by_id('362', :redis => @redis)
    contact.add_tags('admin')

    entity_name = 'abc-123'

    entity = Flapjack::Data::Entity.add({'id'   => '5000',
                                         'name' => entity_name,
                                         'contacts' => ['362']},
                                         :redis => @redis)

    expect {
      expect {
        expect {
          contact.delete!
        }.to change { Flapjack::Data::Contact.all(:redis => @redis).size }.by(-1)
      }.to change { @redis.smembers('contact_tag:admin').size }.by(-1)
    }.to change { entity.contacts.size }.by(-1)
  end

  it "deletes all contacts"

  it "returns a list of entities and their checks for a contact" do
    entity_name = 'abc-123'

    Flapjack::Data::Entity.add({'id'   => '5000',
                                'name' => entity_name,
                                'contacts' => ['362']},
                                :redis => @redis)

    ec = Flapjack::Data::EntityCheck.for_entity_name(entity_name, 'PING', :redis => @redis)
    t = Time.now.to_i
    ec.update_state('ok', :timestamp => t, :summary => 'a')
    ec.last_update = t

    contact = Flapjack::Data::Contact.find_by_id('362', :redis => @redis)
    eandcs = contact.entities(:checks => true)
    eandcs.should_not be_nil
    eandcs.should be_an(Array)
    eandcs.should have(1).entity_and_checks

    eandc = eandcs.first
    eandc.should be_a(Hash)

    entity = eandc[:entity]
    entity.name.should == entity_name
    checks = eandc[:checks]
    checks.should be_a(Set)
    checks.should have(1).check
    checks.should include('PING')
  end

  it "returns pagerduty credentials for a contact" do
    contact = Flapjack::Data::Contact.find_by_id('362', :redis => @redis)
    credentials = contact.pagerduty_credentials
    credentials.should_not be_nil
    credentials.should be_a(Hash)
    credentials.should == {'service_key' => '123456789012345678901234',
                           'subdomain'   => 'flpjck',
                           'username'    => 'flapjack',
                           'password'    => 'very_secure'}
  end

end
