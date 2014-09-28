Pact.provider_states_for "flapjack-diner" do

  provider_state "no contact exists" do
    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      Flapjack.redis.flushdb
    end
  end

  provider_state "no entity exists" do
    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      Flapjack.redis.flushdb
    end
  end

  provider_state "no check exists" do
    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      Flapjack.redis.flushdb
    end
  end

  provider_state "no notification rule exists" do
    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      Flapjack.redis.flushdb
    end
  end

  provider_state "an entity 'www.example.com' with id '1234' exists" do
    set_up do
      entity = Flapjack::Data::Entity.new(:id => '1234', :name => 'www.example.com',
        :enabled => true)
      entity.save
    end

    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      Flapjack.redis.flushdb
    end
  end

  provider_state "entities 'www.example.com', id '1234' and 'www2.example.com', id '5678' exist" do
    set_up do
      entity = Flapjack::Data::Entity.new(:id => '1234', :name => 'www.example.com',
        :enabled => true)
      entity.save

      entity_2 = Flapjack::Data::Entity.new(:id => '5678', :name => 'www2.example.com',
        :enabled => true)
      entity_2.save
    end

    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      Flapjack.redis.flushdb
    end
  end

  provider_state "a check 'www.example.com:SSH' exists" do
    set_up do
      entity = Flapjack::Data::Entity.new(:id => '1234', :name => 'www.example.com',
        :enabled => true)
      entity.save

      check = Flapjack::Data::Check.new(:name => 'SSH')
      check.save

      entity.checks << check
    end

    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      Flapjack.redis.flushdb
    end
  end

  provider_state "checks 'www.example.com:SSH' and 'www2.example.com:PING' exist" do
    set_up do
      entity = Flapjack::Data::Entity.new(:id => '1234', :name => 'www.example.com',
        :enabled => true)
      entity.save

      check = Flapjack::Data::Check.new(:name => 'SSH')
      check.save

      entity.checks << check

      entity_2 = Flapjack::Data::Entity.new(:id => '5678', :name => 'www2.example.com',
        :enabled => true)
      entity_2.save

      check_2 = Flapjack::Data::Check.new(:name => 'PING')
      check_2.save

      entity_2.checks << check_2
    end

    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      Flapjack.redis.flushdb
    end
  end

  provider_state "a contact with id 'abc' exists" do
    set_up do
      contact = Flapjack::Data::Contact.new(
        :id         => 'abc',
        :first_name => 'Jim',
        :last_name  => 'Smith',
        :email      => 'jims@example.com',
        :timezone   => 'UTC',
        :tags       => ['admin', 'night_shift']
      )
      contact.save
    end

    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      Flapjack.redis.flushdb
    end
  end

  provider_state "a contact with id 'abc' has email and sms media" do
    set_up do
      contact = Flapjack::Data::Contact.new(
        :id         => 'abc',
        :first_name => 'Jim',
        :last_name  => 'Smith',
        :email      => 'jims@example.com',
        :timezone   => 'UTC',
        :tags       => ['admin', 'night_shift']
      )
      contact.save

      medium_email = Flapjack::Data::Medium.new(
        :type             => 'email',
        :address          => 'ablated@example.org',
        :interval         => 180,
        :rollup_threshold => 3
      )
      medium_email.save

      medium_sms = Flapjack::Data::Medium.new(
        :type             => 'sms',
        :address          => '0123456789',
        :interval         => 300,
        :rollup_threshold => 5
      )
      medium_sms.save

      contact.media.add(medium_email, medium_sms)
    end

    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      Flapjack.redis.flushdb
    end
  end

  provider_state "a contact with id '872' exists" do
    set_up do
      contact = Flapjack::Data::Contact.new(
        :id         => '872',
        :first_name => 'John',
        :last_name  => 'Smith',
        :email      => 'jsmith@example.com',
      )
      contact.save
    end

    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      Flapjack.redis.flushdb
    end
  end

  provider_state "contacts with ids 'abc' and '872' exist" do
    set_up do
      contact = Flapjack::Data::Contact.new(
        :id         => 'abc',
        :first_name => 'Jim',
        :last_name  => 'Smith',
        :email      => 'jims@example.com',
        :timezone   => 'UTC',
        :tags       => ['admin', 'night_shift']
      )
      contact.save

      contact_2 = Flapjack::Data::Contact.new(
        :id         => '872',
        :first_name => 'John',
        :last_name  => 'Smith',
        :email      => 'jsmith@example.com',
      )
      contact_2.save
    end

    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      Flapjack.redis.flushdb
    end
  end

  provider_state "a contact 'abc' with generic notification rule '05983623-fcef-42da-af44-ed6990b500fa' exists" do
    set_up do
      contact = Flapjack::Data::Contact.new(
        :id         => 'abc',
        :first_name => 'Jim',
        :last_name  => 'Smith',
        :email      => 'jims@example.com',
        :timezone   => 'UTC',
        :tags       => ['admin', 'night_shift']
      )
      contact.save

      existing_nr = contact.notification_rules.first

      notification_rule = Flapjack::Data::NotificationRule.new(
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
      )
      contact.notification_rules << nr_data
      existing_nr.destroy
    end

    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      Flapjack.redis.flushdb
    end
  end

  provider_state "a contact 'abc' with generic notification rule '05983623-fcef-42da-af44-ed6990b500fa' and notification rule '20f182fc-6e32-4794-9007-97366d162c51' exists" do
    set_up do
      contact = Flapjack::Data::Contact.new(
        :id         => 'abc',
        :first_name => 'Jim',
        :last_name  => 'Smith',
        :email      => 'jims@example.com',
        :timezone   => 'UTC',
        :tags       => ['admin', 'night_shift']
      )
      contact.save

      existing_nr = contact.notification_rules.first

      notification_rule = Flapjack::Data::NotificationRule.new(
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
      )
      contact.notification_rules << notification_rule
      existing_nr.destroy

      notification_rule_2 = Flapjack::Data::NotificationRule.new(
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
      )
      contact.notification_rules << notification_rule_2
    end

    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      Flapjack.redis.flushdb
    end
  end

  provider_state "a contact with id 'abc' has pagerduty credentials" do
    set_up do
      contact = Flapjack::Data::Contact.new(
        :id         => 'abc',
        :first_name => 'Jim',
        :last_name  => 'Smith',
        :email      => 'jims@example.com',
        :timezone   => 'UTC',
        :tags       => ['admin', 'night_shift']
      )
      contact.save

      pdc = Flapjack::Data::PagerdutyCredentials.new(
        :service_key => 'abc',
        :subdomain   => 'def',
        :username    => 'ghi',
        :password    => 'jkl',
      )
      contact.pagerduty_credentials = pdc
    end

    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      Flapjack.redis.flushdb
    end
  end

  provider_state "contacts with ids 'abc' and '872' have pagerduty credentials" do
    set_up do
      contact = Flapjack::Data::Contact.new(
        :id         => 'abc',
        :first_name => 'Jim',
        :last_name  => 'Smith',
        :email      => 'jims@example.com',
        :timezone   => 'UTC',
        :tags       => ['admin', 'night_shift']
      )
      contact.save

      pdc = Flapjack::Data::PagerdutyCredentials.new(
        :service_key => 'abc',
        :subdomain   => 'def',
        :username    => 'ghi',
        :password    => 'jkl',
      )
      contact.pagerduty_credentials = pdc

      contact_2 = Flapjack::Data::Contact.new(
        :id         => '872',
        :first_name => 'John',
        :last_name  => 'Smith',
        :email      => 'jsmith@example.com',
      )
      contact_2.save

      pdc_2 = Flapjack::Data::PagerdutyCredentials.new(
        :service_key => 'mno',
        :subdomain   => 'pqr',
        :username    => 'stu',
        :password    => 'vwx',
      )
      contact_2.pagerduty_credentials = pdc_2
    end

    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      Flapjack.redis.flushdb
    end
  end

end