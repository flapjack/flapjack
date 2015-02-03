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
            'subdomain'   => 'flpjck',
            'username'    => 'flapjack',
            'password'    => 'very_secure'
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

end