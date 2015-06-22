require 'spec_helper'

require 'flapjack/data/contact'

describe Flapjack::Data::Contact, :redis => true do

  let(:notification_rule_data) {
    {:tags               => ["database","physical"],
     :entities           => ["foo-app-01.example.com"],
     :time_restrictions  => [],
     :unknown_media      => [],
     :warning_media      => ["email"],
     :critical_media     => ["sms", "email"],
     :unknown_blackhole  => false,
     :warning_blackhole  => false,
     :critical_blackhole => false
    }
  }

  let(:general_notification_rule_data) {
    {:entities           => [],
     :tags               => Set.new([]),
     :time_restrictions  => [],
     :unknown_media      => [],
     :warning_media      => ['email', 'sms', 'slack', 'sms_twilio', 'sms_nexmo', 'jabber', 'pagerduty', 'sns'],
     :critical_media     => ['email', 'sms', 'slack', 'sms_twilio', 'sms_nexmo', 'jabber', 'pagerduty', 'sns'],
     :unknown_blackhole  => false,
     :warning_blackhole  => false,
     :critical_blackhole => false}
  }

  before(:each) do
    Flapjack::Data::Contact.add( {
        'id'         => 'c362',
        'first_name' => 'John',
        'last_name'  => 'Johnson',
        'email'      => 'johnj@example.com',
        'media'      => {
          'pagerduty' => {
            'service_key' => '123456789012345678901234',
            'subdomain'   => 'flpjck',
            'token'       => 'token123',
            'username'    => nil,
            'password'    => nil
          },
        },
      },
      :redis => @redis)

    Flapjack::Data::Contact.add( {
        'id'         => 'c363_a-f@42%*',
        'first_name' => 'Jane',
        'last_name'  => 'Janeley',
        'email'      => 'janej@example.com',
        'media'      => {
          'email' => {
            'address'          => 'janej@example.com',
            'interval'         => 60,
            'rollup_threshold' => 5,
          },
        },
      },
      :redis => @redis)
  end

  it "returns a list of all contacts" do
    contacts = Flapjack::Data::Contact.all(:redis => @redis)
    expect(contacts).not_to be_nil
    expect(contacts).to be_an(Array)
    expect(contacts.size).to eq(2)
    expect(contacts[0].name).to eq('Jane Janeley')
    expect(contacts[1].name).to eq('John Johnson')
  end

  it "finds a contact by id" do
    contact = Flapjack::Data::Contact.find_by_id('c362', :redis => @redis)
    expect(contact).not_to be_nil
    expect(contact.name).to eq("John Johnson")
  end

  it "finds contacts by ids" do
    contacts = Flapjack::Data::Contact.find_by_ids(['c362','c363_a-f@42%*'], :redis => @redis)
    expect(contacts).not_to be_nil
    expect(contacts.length).to eq(2)
    contact = contacts.first
    expect(contact.name).to eq("John Johnson")
  end

  it "adds a contact with the same id as an existing one, clears notification rules" do
    contact = Flapjack::Data::Contact.find_by_id('c363_a-f@42%*', :redis => @redis)
    expect(contact).not_to be_nil

    contact.add_notification_rule(notification_rule_data)

    nr = contact.notification_rules
    expect(nr).not_to be_nil
    expect(nr.size).to eq(2)

    Flapjack::Data::Contact.add({'id'         => 'c363_a-f@42%*',
                                 'first_name' => 'Smithy',
                                 'last_name'  => 'Smith',
                                 'email'      => 'smithys@example.com'},
                                 :redis       => @redis)

    contact = Flapjack::Data::Contact.find_by_id('c363_a-f@42%*', :redis => @redis)
    expect(contact).not_to be_nil
    expect(contact.name).to eq('Smithy Smith')
    rules = contact.notification_rules
    expect(rules.size).to eq(1)
    expect(nr.map(&:id)).not_to include(rules.first.id)
  end

  it "updates a contact and clears their media settings" do
    contact = Flapjack::Data::Contact.find_by_id('c363_a-f@42%*', :redis => @redis)

    contact.update('media' => {})
    expect(contact.media).to be_empty
  end

  it "updates a contact's timezone" do
    contact = Flapjack::Data::Contact.find_by_id('c363_a-f@42%*', :redis => @redis)

    expect(contact.time_zone).to eq(nil)
    contact.update('timezone' => 'Asia/Shanghai')
    expect(contact.time_zone).to eq(ActiveSupport::TimeZone['Asia/Shanghai'])
  end

  it "clears a contact's timezone with a nil value" do
    contact = Flapjack::Data::Contact.find_by_id('c363_a-f@42%*', :redis => @redis)

    expect(contact.time_zone).to eq(nil)
    contact.update('timezone' => 'Asia/Shanghai')
    expect(contact.time_zone).to eq(ActiveSupport::TimeZone['Asia/Shanghai'])
    contact.update('timezone' => nil)
    expect(contact.time_zone).to eq(nil)
  end

  it "does not update a contact's timezone with an invalid string" do
    contact = Flapjack::Data::Contact.find_by_id('c363_a-f@42%*', :redis => @redis)

    expect(contact.time_zone).to eq(nil)
    contact.update('timezone' => 'Asia/Shanghai')
    expect(contact.time_zone).to eq(ActiveSupport::TimeZone['Asia/Shanghai'])
    contact.update('timezone' => '')
    expect(contact.time_zone).to eq(ActiveSupport::TimeZone['Asia/Shanghai'])
  end

  it "updates a contact, does not clear notification rules" do
    contact = Flapjack::Data::Contact.find_by_id('c363_a-f@42%*', :redis => @redis)
    expect(contact).not_to be_nil

    contact.add_notification_rule(notification_rule_data)

    nr1 = contact.notification_rules
    expect(nr1).not_to be_nil
    expect(nr1.size).to eq(2)

    contact.update('first_name' => 'John',
                   'last_name'  => 'Smith',
                   'email'      => 'johns@example.com')
    expect(contact.name).to eq('John Smith')

    nr2 = contact.notification_rules
    expect(nr2).not_to be_nil
    expect(nr2.size).to eq(2)
    expect(nr1.map(&:id)).to eq(nr2.map(&:id))
  end

  it "adds a notification rule for a contact" do
    contact = Flapjack::Data::Contact.find_by_id('c363_a-f@42%*', :redis => @redis)
    expect(contact).not_to be_nil

    expect {
      contact.add_notification_rule(notification_rule_data)
    }.to change { contact.notification_rules.size }.from(1).to(2)
  end

  it "removes a notification rule from a contact" do
    contact = Flapjack::Data::Contact.find_by_id('c363_a-f@42%*', :redis => @redis)
    expect(contact).not_to be_nil

    rule = contact.add_notification_rule(notification_rule_data)

    expect {
      contact.delete_notification_rule(rule)
    }.to change { contact.notification_rules.size }.from(2).to(1)
  end

  it "creates a general notification rule for a pre-existing contact if none exists" do
    contact = Flapjack::Data::Contact.find_by_id('c363_a-f@42%*', :redis => @redis)

    @redis.smembers("contact_notification_rules:c363_a-f@42%*").each do |rule_id|
      @redis.srem("contact_notification_rules:c363_a-f@42%*", rule_id)
    end
    expect(@redis.smembers("contact_notification_rules:c363_a-f@42%*")).to be_empty

    rules = contact.notification_rules
    expect(rules.size).to eq(1)
    rule = rules.first
    [:entities, :tags, :time_restrictions,
     :warning_media, :critical_media,
     :warning_blackhole, :critical_blackhole].each do |k|
      expect(rule.send(k)).to eq(general_notification_rule_data[k])
    end
  end

  it "creates a general notification rule for a pre-existing contact if the existing general one was changed" do
    contact = Flapjack::Data::Contact.find_by_id('c363_a-f@42%*', :redis => @redis)
    rules = contact.notification_rules
    expect(rules.size).to eq(1)
    rule = rules.first

    rule.update(notification_rule_data)

    rules = contact.notification_rules
    expect(rules.size).to eq(2)
    expect(rules.select {|r| r.is_specific? }.size).to eq(1)
  end

  it "deletes a contact by id, including linked entities, checks and notification rules" do
    contact = Flapjack::Data::Contact.find_by_id('c362', :redis => @redis)

    entity_name = 'abc-123'

    entity = Flapjack::Data::Entity.add({'id'   => '5000',
                                         'name' => entity_name,
                                         'contacts' => ['c362']},
                                         :redis => @redis)

    expect {
      expect {
        contact.delete!
      }.to change { Flapjack::Data::Contact.all(:redis => @redis).size }.by(-1)
    }.to change { entity.contacts.size }.by(-1)
  end

  it "deletes all contacts"

  it "returns a list of entities and their checks for a contact" do
    entity_name = 'abc-123'

    Flapjack::Data::Entity.add({'id'   => '5000',
                                'name' => entity_name,
                                'contacts' => ['c362']},
                                :redis => @redis)

    ec = Flapjack::Data::EntityCheck.for_entity_name(entity_name, 'PING', :redis => @redis)
    t = Time.now.to_i
    ec.update_state('ok', :timestamp => t, :summary => 'a')
    # was check.last_update=
    @redis.hset("check:#{entity_name}:PING", 'last_update', t)
    @redis.zadd("all_checks", t, @key)
    @redis.zadd("all_checks:#{entity_name}", t, 'PING')
    @redis.zadd("current_checks:#{entity_name}", t, 'PING')
    @redis.zadd('current_entities', t, entity_name)

    contact = Flapjack::Data::Contact.find_by_id('c362', :redis => @redis)
    eandcs = contact.entities(:checks => true)
    expect(eandcs).not_to be_nil
    expect(eandcs).to be_an(Array)
    expect(eandcs.size).to eq(1)

    eandc = eandcs.first
    expect(eandc).to be_a(Hash)

    entity = eandc[:entity]
    expect(entity.name).to eq(entity_name)
    checks = eandc[:checks]
    expect(checks).to be_a(Set)
    expect(checks.size).to eq(1)
    expect(checks).to include('PING')
  end

  it "returns pagerduty credentials for a contact" do
    contact = Flapjack::Data::Contact.find_by_id('c362', :redis => @redis)
    credentials = contact.pagerduty_credentials
    expect(credentials).not_to be_nil
    expect(credentials).to be_a(Hash)
    expect(credentials).to eq({'service_key' => '123456789012345678901234',
                               'subdomain'   => 'flpjck',
                               'token'       => 'token123',
                               'username'    => '',
                               'password'    => ''})
  end

  it "sets pagerduty credentials for a contact" do
    contact = Flapjack::Data::Contact.find_by_id('c362', :redis => @redis)
    contact.set_pagerduty_credentials('service_key' => '567890123456789012345678',
                                      'subdomain'   => 'eggs',
                                      'token'       => 'token123',
                                      'username'    => 'mary',
                                      'password'    => 'mary_password')

    expect(@redis.hget('contact_media:c362', 'pagerduty')).to eq('567890123456789012345678')
    expect(@redis.hgetall('contact_pagerduty:c362')).to eq({
      'subdomain'   => 'eggs',
      'token'       => 'token123',
      'username'    => 'mary',
      'password'    => 'mary_password'
    })
  end

  it "sets the interval for a contact's media" do
    contact = Flapjack::Data::Contact.find_by_id('c362', :redis => @redis)
    contact.set_interval_for_media('email', 42)
    email_interval_raw = @redis.hget("contact_media_intervals:#{contact.id}", 'email')
    expect(email_interval_raw).to eq('42')
  end

  it "returns the interval for a contact's media" do
    contact = Flapjack::Data::Contact.find_by_id('c363_a-f@42%*', :redis => @redis)
    email_interval = contact.interval_for_media('email')
    expect(email_interval).to eq(60)
  end

  it "returns default 15 mins for interval for a contact's media that has no set interval" do
    contact = Flapjack::Data::Contact.find_by_id('c362', :redis => @redis)
    email_interval = contact.interval_for_media('email')
    expect(email_interval).to eq(900)
  end

  it "removes the interval for a contact's media" do
    contact = Flapjack::Data::Contact.find_by_id('c363_a-f@42%*', :redis => @redis)
    contact.set_interval_for_media('email', nil)
    email_interval_raw = @redis.hget("contact_media_intervals:#{contact.id}", 'email')
    expect(email_interval_raw).to be_nil
  end

  it "sets the rollup threshold for a contact's media" do
    contact = Flapjack::Data::Contact.find_by_id('c362', :redis => @redis)
    email_rollup_threshold = contact.set_rollup_threshold_for_media('email', 3)
    email_rollup_threshold_raw = @redis.hget("contact_media_rollup_thresholds:#{contact.id}", 'email')
    expect(email_rollup_threshold_raw).to eq('3')
  end

  it "returns the rollup threshold for a contact's media" do
    contact = Flapjack::Data::Contact.find_by_id('c363_a-f@42%*', :redis => @redis)
    email_rollup_threshold = contact.rollup_threshold_for_media('email')
    expect(email_rollup_threshold).not_to be_nil
    expect(email_rollup_threshold).to be_a(Integer)
    expect(email_rollup_threshold).to eq(5)
  end

  it "removes the rollup threshold for a contact's media" do
    contact = Flapjack::Data::Contact.find_by_id('c363_a-f@42%*', :redis => @redis)
    email_rollup_threshold = contact.set_rollup_threshold_for_media('email', nil)
    email_rollup_threshold_raw = @redis.hget("contact_media_rollup_thresholds:#{contact.id}", 'email')
    expect(email_rollup_threshold_raw).to be_nil
  end

  it "sets the address for a contact's media" do
    contact = Flapjack::Data::Contact.find_by_id('c362', :redis => @redis)
    contact.set_address_for_media('email', 'spongebob@example.com')
    email_address_raw = @redis.hget("contact_media:#{contact.id}", 'email')
    expect(email_address_raw).to eq('spongebob@example.com')
  end

  it "removes a contact's media" do
    contact = Flapjack::Data::Contact.find_by_id('c363_a-f@42%*', :redis => @redis)
    contact.remove_media('email')
    email_address_raw = @redis.hget("contac_media:#{contact.id}", 'email')
    expect(email_address_raw).to be_nil
    email_rollup_threshold_raw = @redis.hget("contact_media_rollup_thresholds:#{contact.id}", 'email')
    expect(email_rollup_threshold_raw).to be_nil
    email_interval_raw = @redis.hget("contact_media_intervals:#{contact.id}", 'email')
    expect(email_interval_raw).to be_nil
  end

end
