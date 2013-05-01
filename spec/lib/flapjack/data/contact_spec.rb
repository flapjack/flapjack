require 'spec_helper'

require 'active_support/time_with_zone'
require 'ice_cube'

require 'flapjack/data/contact'
require 'flapjack/data/entity_check'
require 'flapjack/data/notification_rule'

describe Flapjack::Data::Contact, :redis => true do

  let(:weekdays_8_18) {
    wd = IceCube::Schedule.new(Time.local(2013,2,1,8,0,0), :duration => 60 * 60 * 10)
    wd.add_recurrence_rule(IceCube::Rule.weekly.day(:monday, :tuesday, :wednesday, :thursday, :friday))
    wd
  }

  let(:notification_rule_data) {
    {:entity_tags        => ["database","physical"],
     :entities           => ["foo-app-01.example.com"],
     :time_restrictions  => [ weekdays_8_18.to_hash ],
     :warning_media      => ["email"],
     :critical_media     => ["sms", "email"],
     :warning_blackhole  => false,
     :critical_blackhole => false
    }
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
                                 'email'      => 'janej@example.com'},
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
    nr.should have(1).notification_rule

    Flapjack::Data::Contact.add({'id'         => '363',
                                 'first_name' => 'Smithy',
                                 'last_name'  => 'Smith',
                                 'email'      => 'smithys@example.com'},
                                 :redis       => @redis)

    contact = Flapjack::Data::Contact.find_by_id('363', :redis => @redis)
    contact.should_not be_nil
    contact.name.should == 'Smithy Smith'

    nr = contact.notification_rules
    nr.should_not be_nil
    nr.should be_empty
  end

  it "updates a contact, does not clear notification rules" do
    contact = Flapjack::Data::Contact.find_by_id('363', :redis => @redis)
    contact.should_not be_nil

    contact.add_notification_rule(notification_rule_data)

    nr = contact.notification_rules
    nr.should_not be_nil
    nr.should have(1).notification_rule

    contact.update('first_name' => 'John',
                   'last_name'  => 'Smith',
                   'email'      => 'johns@example.com')
    contact.name.should == 'John Smith'

    nr = contact.notification_rules
    nr.should_not be_nil
    nr.should have(1).notification_rule
  end

  it "adds a notification rule for a contact" do
    contact = Flapjack::Data::Contact.find_by_id('363', :redis => @redis)
    contact.should_not be_nil

    expect {
      contact.add_notification_rule(notification_rule_data)
    }.to change { contact.notification_rules.size }.from(0).to(1)
  end

  it "removes a notification rule from a contact" do
    contact = Flapjack::Data::Contact.find_by_id('363', :redis => @redis)
    contact.should_not be_nil

    rule = contact.add_notification_rule(notification_rule_data)

    expect {
      contact.delete_notification_rule(rule)
    }.to change { contact.notification_rules.size }.from(1).to(0)
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
