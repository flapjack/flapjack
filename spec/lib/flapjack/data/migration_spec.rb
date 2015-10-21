require 'spec_helper'
require 'flapjack/data/migration'
require 'flapjack/data/notification_rule'

describe Flapjack::Data::Migration, :redis => true do

  it 'removes an orphaned entity id' do
    @redis.hset('all_entity_ids_by_name', 'name_1', 'id_2')
    @redis.hset('all_entity_names_by_id', 'id_1', 'name_1')
    @redis.hset('all_entity_names_by_id', 'id_2', 'name_1')

    Flapjack::Data::Migration.clear_orphaned_entity_ids(:redis => @redis)

    expect(@redis.hgetall('all_entity_ids_by_name')).to eq('name_1' => 'id_2')
    expect(@redis.hgetall('all_entity_names_by_id')).to eq('id_2' => 'name_1')
  end

  it "fixes a notification rule wih no contact association" do
    contact = Flapjack::Data::Contact.add( {
        'id'         => 'c362',
        'first_name' => 'John',
        'last_name'  => 'Johnson',
        'email'      => 'johnj@example.com',
        'media'      => {
          'pagerduty' => {
            'service_key' => '123456789012345678901234',
            'subdomain'   => 'flpjck'
          },
        },
      },
      :redis => @redis)

    rule = contact.add_notification_rule(
     :tags               => ["database","physical"],
     :entities           => ["foo-app-01.example.com"],
     :time_restrictions  => [],
     :unknown_media      => [],
     :warning_media      => ["email"],
     :critical_media     => ["sms", "email"],
     :unknown_blackhole  => false,
     :warning_blackhole  => false,
     :critical_blackhole => false
    )

    rule_id = rule.id

    # degrade as the bug had previously
    @redis.hset("notification_rule:#{rule.id}", 'contact_id', '')

    rule = Flapjack::Data::NotificationRule.find_by_id(rule_id, :redis => @redis)
    expect(rule).not_to be_nil
    expect(rule.contact_id).to be_empty

    Flapjack::Data::Migration.correct_notification_rule_contact_linkages(:redis => @redis)

    rule = Flapjack::Data::NotificationRule.find_by_id(rule_id, :redis => @redis)
    expect(rule).not_to be_nil
    expect(rule.contact_id).to eq(contact.id)
  end

  it "removes a disabled check from a medium's alerting checks" do
    contact = Flapjack::Data::Contact.add( {
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

    entity = Flapjack::Data::Entity.add({ 'id'   => '5000',
                                          'name' => 'abc-123',
                                          'contacts' => ['c363_a-f@42%*'] },
                                          :redis => @redis)

    entity_check_ping = Flapjack::Data::EntityCheck.for_entity_name('abc-123', 'ping', :redis => @redis)
    entity_check_ping.update_state('critical')

    entity_check_ssh  = Flapjack::Data::EntityCheck.for_entity_name('abc-123', 'ssh', :redis => @redis)
    entity_check_ssh.update_state('critical')

    contact.add_alerting_check_for_media('email', 'abc-123:ping')
    contact.add_alerting_check_for_media('email', 'abc-123:ssh')

    expect(contact.alerting_checks_for_media('email')).to eq(['abc-123:ping', 'abc-123:ssh'])

    entity_check_ssh.disable!

    expect(contact.alerting_checks_for_media('email')).to eq(['abc-123:ping', 'abc-123:ssh'])

    Flapjack::Data::Migration.correct_rollup_including_disabled_checks(:redis => @redis)

    expect(contact.alerting_checks_for_media('email')).to eq(['abc-123:ping'])
  end

end