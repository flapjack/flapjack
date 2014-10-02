Pact.provider_states_for "flapjack-diner" do

  provider_state "no contact exists" do
    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      redis = Flapjack::Gateways::JSONAPI.instance_variable_get('@redis')
      redis.flushdb
    end
  end

  provider_state "no entity exists" do
    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      redis = Flapjack::Gateways::JSONAPI.instance_variable_get('@redis')
      redis.flushdb
    end
  end

  provider_state "no check exists" do
    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      redis = Flapjack::Gateways::JSONAPI.instance_variable_get('@redis')
      redis.flushdb
    end
  end

  provider_state "no notification rule exists" do
    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      redis = Flapjack::Gateways::JSONAPI.instance_variable_get('@redis')
      redis.flushdb
    end
  end

  provider_state "an entity 'www.example.com' with id '1234' exists" do
    set_up do
      redis = Flapjack::Gateways::JSONAPI.instance_variable_get('@redis')

      entity_data = {'id' => '1234', 'name' => 'www.example.com'}
      Flapjack::Data::Entity.add(entity_data, :redis => redis)
    end

    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      redis = Flapjack::Gateways::JSONAPI.instance_variable_get('@redis')
      redis.flushdb
    end
  end

  provider_state "entities 'www.example.com', id '1234' and 'www2.example.com', id '5678' exist" do
    set_up do
      redis = Flapjack::Gateways::JSONAPI.instance_variable_get('@redis')

      entity_data = {'id' => '1234', 'name' => 'www.example.com'}
      Flapjack::Data::Entity.add(entity_data, :redis => redis)
      entity_data_2 = {'id' => '5678', 'name' => 'www2.example.com'}
      Flapjack::Data::Entity.add(entity_data_2, :redis => redis)
    end

    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      redis = Flapjack::Gateways::JSONAPI.instance_variable_get('@redis')
      redis.flushdb
    end
  end

  provider_state "a check 'www.example.com:SSH' exists" do
    set_up do
      redis = Flapjack::Gateways::JSONAPI.instance_variable_get('@redis')

      entity_data = {'id' => '1234', 'name' => 'www.example.com'}
      Flapjack::Data::Entity.add(entity_data, :redis => redis)
      check_data = {'entity_id' => '1234', 'name' => 'SSH'}
      Flapjack::Data::EntityCheck.add(check_data, :redis => redis)
    end

    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      redis = Flapjack::Gateways::JSONAPI.instance_variable_get('@redis')
      redis.flushdb
    end
  end

  provider_state "checks 'www.example.com:SSH' and 'www2.example.com:PING' exist" do
    set_up do
      redis = Flapjack::Gateways::JSONAPI.instance_variable_get('@redis')

      entity_data = {'id' => '1234', 'name' => 'www.example.com'}
      Flapjack::Data::Entity.add(entity_data, :redis => redis)
      entity_data_2 = {'id' => '5678', 'name' => 'www2.example.com'}
      Flapjack::Data::Entity.add(entity_data_2, :redis => redis)

      check_data = {'entity_id' => '1234', 'name' => 'SSH'}
      Flapjack::Data::EntityCheck.add(check_data, :redis => redis)
      check_data_2 = {'entity_id' => '5678', 'name' => 'PING'}
      Flapjack::Data::EntityCheck.add(check_data_2, :redis => redis)
    end

    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      redis = Flapjack::Gateways::JSONAPI.instance_variable_get('@redis')
      redis.flushdb
    end
  end

  provider_state "a contact with id 'abc' exists" do
    set_up do
      redis = Flapjack::Gateways::JSONAPI.instance_variable_get('@redis')
      contact_data = {'id'         => 'abc',
                      'first_name' => 'Jim',
                      'last_name'  => 'Smith',
                      'email'      => 'jims@example.com',
                      'timezone'   => 'UTC',
                      'tags'       => ['admin', 'night_shift']}
      Flapjack::Data::Contact.add(contact_data, :redis => redis)
    end

    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      redis = Flapjack::Gateways::JSONAPI.instance_variable_get('@redis')
      redis.flushdb
    end
  end

  provider_state "a contact with id 'abc' has email and sms media" do
    set_up do
      redis = Flapjack::Gateways::JSONAPI.instance_variable_get('@redis')
      contact_data = {'id'         => 'abc',
                      'first_name' => 'Jim',
                      'last_name'  => 'Smith',
                      'email'      => 'jims@example.com',
                      'timezone'   => 'UTC',
                      'tags'       => ['admin', 'night_shift']}
      contact = Flapjack::Data::Contact.add(contact_data, :redis => redis)

      email_data = {
        'type'             => 'email',
        'address'          => 'ablated@example.org',
        'interval'         => 180,
        'rollup_threshold' => 3
      }

      sms_data = {
        'type'             => 'sms',
        'address'          => '0123456789',
        'interval'         => 300,
        'rollup_threshold' => 5
      }

      [email_data, sms_data].each do |medium_data|
        type = medium_data['type']
        contact.set_address_for_media(type, medium_data['address'])
        contact.set_interval_for_media(type, medium_data['interval'])
        contact.set_rollup_threshold_for_media(type, medium_data['rollup_threshold'])
      end
    end

    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      redis = Flapjack::Gateways::JSONAPI.instance_variable_get('@redis')
      redis.flushdb
    end
  end

  provider_state "a contact with id '872' exists" do
    set_up do
      redis = Flapjack::Gateways::JSONAPI.instance_variable_get('@redis')
      contact_data = {'id' => '872', 'first_name' => 'John',
                      'last_name' => 'Smith', 'email' => 'jsmith@example.com'}
      Flapjack::Data::Contact.add(contact_data, :redis => redis)
    end

    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      redis = Flapjack::Gateways::JSONAPI.instance_variable_get('@redis')
      redis.flushdb
    end
  end

  provider_state "contacts with ids 'abc' and '872' exist" do
    set_up do
      redis = Flapjack::Gateways::JSONAPI.instance_variable_get('@redis')
      contact_data = {'id'         => 'abc',
                      'first_name' => 'Jim',
                      'last_name'  => 'Smith',
                      'email'      => 'jims@example.com',
                      'timezone'   => 'UTC',
                      'tags'       => ['admin', 'night_shift']}
      Flapjack::Data::Contact.add(contact_data, :redis => redis)
      contact_data_2 = {'id'         => '872',
                        'first_name' => 'John',
                        'last_name'  => 'Smith',
                        'email'      => 'jsmith@example.com'}
      Flapjack::Data::Contact.add(contact_data_2, :redis => redis)
    end

    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      redis = Flapjack::Gateways::JSONAPI.instance_variable_get('@redis')
      redis.flushdb
    end
  end

  provider_state "a contact 'abc' with generic notification rule '05983623-fcef-42da-af44-ed6990b500fa' exists" do
    set_up do
      redis = Flapjack::Gateways::JSONAPI.instance_variable_get('@redis')

      contact_data = {'id'         => 'abc',
                      'first_name' => 'Jim',
                      'last_name'  => 'Smith',
                      'email'      => 'jims@example.com',
                      'timezone'   => 'UTC',
                      'tags'       => ['admin', 'night_shift']}
      contact = Flapjack::Data::Contact.add(contact_data, :redis => redis)
      existing_nr = contact.notification_rules.first

      nr_data = {
        :id                 => '05983623-fcef-42da-af44-ed6990b500fa',
        :tags               => [],
        :regex_tags         => [],
        :entities           => [],
        :regex_entities     => [],
        :time_restrictions  => [],
        :warning_media      => ["email"],
        :critical_media     => ["sms", "email"],
        :warning_blackhole  => false,
        :critical_blackhole => false
      }
      contact.add_notification_rule(nr_data)
      contact.delete_notification_rule(existing_nr)
    end

    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      redis = Flapjack::Gateways::JSONAPI.instance_variable_get('@redis')
      redis.flushdb
    end
  end

  provider_state "a contact 'abc' with generic notification rule '05983623-fcef-42da-af44-ed6990b500fa' and notification rule '20f182fc-6e32-4794-9007-97366d162c51' exists" do
    set_up do
      redis = Flapjack::Gateways::JSONAPI.instance_variable_get('@redis')

      contact_data = {'id'         => 'abc',
                      'first_name' => 'Jim',
                      'last_name'  => 'Smith',
                      'email'      => 'jims@example.com',
                      'timezone'   => 'UTC',
                      'tags'       => ['admin', 'night_shift']}
      contact = Flapjack::Data::Contact.add(contact_data, :redis => redis)
      existing_nr = contact.notification_rules.first

      nr_data = {
        :id                 => '05983623-fcef-42da-af44-ed6990b500fa',
        :tags               => [],
        :regex_tags         => [],
        :entities           => [],
        :regex_entities     => [],
        :time_restrictions  => [],
        :warning_media      => ["email"],
        :critical_media     => ["sms", "email"],
        :warning_blackhole  => false,
        :critical_blackhole => false
      }
      contact.add_notification_rule(nr_data)

      nr_data_2 = {
        :id                 => '20f182fc-6e32-4794-9007-97366d162c51',
        :tags               => ['physical'],
        :regex_tags         => [],
        :entities           => ['example.com'],
        :regex_entities     => [],
        :time_restrictions  => [],
        :warning_media      => ["email"],
        :critical_media     => ["sms", "email"],
        :warning_blackhole  => true,
        :critical_blackhole => true
      }
      contact.add_notification_rule(nr_data_2)
      contact.delete_notification_rule(existing_nr)
    end

    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      redis = Flapjack::Gateways::JSONAPI.instance_variable_get('@redis')
      redis.flushdb
    end
  end

  provider_state "a contact with id 'abc' has pagerduty credentials" do
    set_up do
      redis = Flapjack::Gateways::JSONAPI.instance_variable_get('@redis')
      contact_data = {'id'         => 'abc',
                      'first_name' => 'Jim',
                      'last_name'  => 'Smith',
                      'email'      => 'jims@example.com',
                      'timezone'   => 'UTC',
                      'tags'       => ['admin', 'night_shift']}
      contact = Flapjack::Data::Contact.add(contact_data, :redis => redis)

      pdc_data = {
        'service_key' => 'abc',
        'subdomain'   => 'def',
        'username'    => 'ghi',
        'password'    => 'jkl',
      }
      contact.set_pagerduty_credentials(pdc_data)
    end

    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      redis = Flapjack::Gateways::JSONAPI.instance_variable_get('@redis')
      redis.flushdb
    end
  end

  provider_state "contacts with ids 'abc' and '872' have pagerduty credentials" do
    set_up do
      redis = Flapjack::Gateways::JSONAPI.instance_variable_get('@redis')
      contact_data = {'id'         => 'abc',
                      'first_name' => 'Jim',
                      'last_name'  => 'Smith',
                      'email'      => 'jims@example.com',
                      'timezone'   => 'UTC',
                      'tags'       => ['admin', 'night_shift']}
      contact = Flapjack::Data::Contact.add(contact_data, :redis => redis)
      contact_data_2 = {'id'         => '872',
                        'first_name' => 'John',
                        'last_name'  => 'Smith',
                        'email'      => 'jsmith@example.com'}
      contact_2 = Flapjack::Data::Contact.add(contact_data_2, :redis => redis)

      pdc_data = {
        'service_key' => 'abc',
        'subdomain'   => 'def',
        'username'    => 'ghi',
        'password'    => 'jkl',
      }
      contact.set_pagerduty_credentials(pdc_data)
      pdc_data_2 = {
        'service_key' => 'mno',
        'subdomain'   => 'pqr',
        'username'    => 'stu',
        'password'    => 'vwx',
    }
    contact_2.set_pagerduty_credentials(pdc_data_2)
    end

    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      redis = Flapjack::Gateways::JSONAPI.instance_variable_get('@redis')
      redis.flushdb
    end
  end

end