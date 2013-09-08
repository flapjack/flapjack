require 'spec_helper'

require 'active_support/time_with_zone'
require 'ice_cube'

require 'flapjack/data/contact_r'
require 'flapjack/data/entity_check'
require 'flapjack/data/notification_rule'
require 'flapjack/data/tag_set'

describe Flapjack::Data::ContactR, :redis => true do

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
     :tags               => [],
     :time_restrictions  => [],
     :warning_media      => ['email', 'sms', 'jabber', 'pagerduty'],
     :critical_media     => ['email', 'sms', 'jabber', 'pagerduty'],
     :warning_blackhole  => false,
     :critical_blackhole => false}
  }

  let(:redis) { Flapjack.redis }

  before(:each) do

    # contact_1_data = {:id         => '362',
    #                 :first_name => 'John',
    #                 :last_name  => 'Johnson',
    #                 :email      => 'johnj@example.com'}

    # 'media' => {
    #   'pagerduty' => {
    #     'service_key' => '123456789012345678901234',
    #     'subdomain'   => 'flpjck',
    #     'username'    => 'flapjack',
    #     'password'    => 'very_secure'
    #   }
    # }

    # contact_1 = Flapjack::Data::ContactR.new(contact_1_data)
    # contact_1.save

    # contact_2_data = {:id         => '363',
    #                   :first_name => 'Jane',
    #                   :last_name  => 'Janeley',
    #                   :email      => 'janej@example.com'}

    # 'media'      => {
    #   'email' => {
    #     'address'  => 'janej@example.com',
    #     'interval' => 60
    #   }
    # }

    # contact_2 = Flapjack::Data::ContactR.new(contact_2_data)
    # contact_2.save

  end

  def create_contact
    redis.hmset('flapjack/data/contact_r:1:attrs', {'first_name' => '"John"',
      'last_name' => '"Smith"', 'email' => '"jsmith@example.com"'}.flatten)
    redis.sadd('flapjack/data/contact_r::ids', '1')
  end

  it "returns a contact's name" do
    create_contact # raw redis
    contact = Flapjack::Data::ContactR.find_by_id('1')

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

  # it "returns pagerduty credentials for a contact" do
  #   contact = Flapjack::Data::Contact.find_by_id('362')
  #   credentials = contact.pagerduty_credentials
  #   credentials.should_not be_nil
  #   credentials.should be_a(Hash)
  #   credentials.should == {'service_key' => '123456789012345678901234',
  #                          'subdomain'   => 'flpjck',
  #                          'username'    => 'flapjack',
  #                          'password'    => 'very_secure'}
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

    it "clears notification rules when re-adding a contact"

    # it "adds a contact with the same id as an existing one, clears notification rules" do
    #   contact = Flapjack::Data::Contact.find_by_id('363')
    #   contact.should_not be_nil

    #   contact.add_notification_rule(notification_rule_data)

    #   nr = contact.notification_rules
    #   nr.should_not be_nil
    #   nr.should have(2).notification_rules

    #   Flapjack::Data::Contact.add({'id'         => '363',
    #                                'first_name' => 'Smithy',
    #                                'last_name'  => 'Smith',
    #                                'email'      => 'smithys@example.com'})

    #   contact = Flapjack::Data::Contact.find_by_id('363')
    #   contact.should_not be_nil
    #   contact.name.should == 'Smithy Smith'
    #   rules = contact.notification_rules
    #   rules.should have(1).notification_rule
    #   nr.map(&:id).should_not include(rules.first.id)
    # end

    it "does not clear notification rules when updating a contact" do
      create_contact # raw redis
      contact = Flapjack::Data::ContactR.find_by_id(1)

      contact.notification_rules_checked.count.should == 1
      rule_id = contact.notification_rules_checked.all.first.id
      contact.first_name = 'Jim'
      contact.save.should be_true
      contact.notification_rules_checked.count.should == 1
      contact.notification_rules_checked.all.first.id.should == rule_id
    end

  # it "updates a contact, does not clear notification rules" do
  #   contact = Flapjack::Data::Contact.find_by_id('363')
  #   contact.should_not be_nil

  #   contact.add_notification_rule(notification_rule_data)

  #   nr1 = contact.notification_rules
  #   nr1.should_not be_nil
  #   nr1.should have(2).notification_rules

  #   contact.update('first_name' => 'John',
  #                  'last_name'  => 'Smith',
  #                  'email'      => 'johns@example.com')
  #   contact.name.should == 'John Smith'

  #   nr2 = contact.notification_rules
  #   nr2.should_not be_nil
  #   nr2.should have(2).notification_rules
  #   nr1.map(&:id).should == nr2.map(&:id)
  # end

    it "creates a general notification rule for a pre-existing contact if none exists" do
      create_contact # raw redis
      contact = Flapjack::Data::ContactR.find_by_id(1)

      expect {
        contact.notification_rules_checked
      }.to change { Flapjack::Data::NotificationRuleR.count }.by(1)
    end

  # it "creates a general notification rule for a pre-existing contact if none exists" do
  #   contact = Flapjack::Data::Contact.find_by_id('363')

  #   Flapjack.redis.smembers("contact_notification_rules:363").each do |rule_id|
  #     Flapjack.redis.srem("contact_notification_rules:363", rule_id)
  #   end
  #   Flapjack.redis.smembers("contact_notification_rules:363").should be_empty

  #   rules = contact.notification_rules
  #   rules.should have(1).rule
  #   rule = rules.first
  #   [:entities, :tags, :time_restrictions,
  #    :warning_media, :critical_media,
  #    :warning_blackhole, :critical_blackhole].each do |k|
  #     rule.send(k).should == general_notification_rule_data[k]
  #   end
  # end


  it "creates a general notification rule for a pre-existing contact if the existing general one was changed" 

  # it "creates a general notification rule for a pre-existing contact if the existing general one was changed" do
  #   contact = Flapjack::Data::Contact.find_by_id('363')
  #   rules = contact.notification_rules
  #   rules.should have(1).notification_rule
  #   rule = rules.first

  #   rule.update(notification_rule_data)

  #   rules = contact.notification_rules
  #   rules.should have(2).notification_rules
  #   rules.select {|r| r.is_specific? }.should have(1).rule
  # end


  end

  context 'timezone' do

    it "sets a timezone string from a string" do
      create_contact # raw redis
      contact = Flapjack::Data::ContactR.find_by_id(1)
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

  # it "returns pagerduty credentials for a contact" do
  #   contact = Flapjack::Data::Contact.find_by_id('362')
  #   credentials = contact.pagerduty_credentials
  #   credentials.should_not be_nil
  #   credentials.should be_a(Hash)
  #   credentials.should == {'service_key' => '123456789012345678901234',
  #                          'subdomain'   => 'flpjck',
  #                          'username'    => 'flapjack',
  #                          'password'    => 'very_secure'}
  # end

end
