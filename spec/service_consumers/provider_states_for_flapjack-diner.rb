Pact.provider_states_for "flapjack-diner" do

  provider_state "no contact exists" do
    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      Flapjack.redis.flushdb
    end
  end

  provider_state "no media exist" do
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

  provider_state "no pagerduty credentials exist" do
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

  provider_state "a check 'www.example.com:SSH' exists" do
    set_up do
      check = Flapjack::Data::Check.new(:name => 'www.example.com:SSH',
        :id => 'www.example.com:SSH')
      check.save
    end

    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      Flapjack.redis.flushdb
    end
  end

  provider_state "checks 'www.example.com:SSH' and 'www2.example.com:PING' exist" do
    set_up do
      check = Flapjack::Data::Check.new(:name => 'www.example.com:SSH',
        :id => 'www.example.com:SSH')
      check.save

      check_2 = Flapjack::Data::Check.new(:name => 'www2.example.com:PING',
        :id => 'www2.example.com:PING')
      check_2.save
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
        # :tags       => ['admin', 'night_shift']
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
        # :tags       => ['admin', 'night_shift']
      )
      contact.save

      medium_email = Flapjack::Data::Medium.new(
        :id               => 'abc_email',
        :type             => 'email',
        :address          => 'ablated@example.org',
        :interval         => 180,
        :rollup_threshold => 3
      )
      medium_email.save

      medium_sms = Flapjack::Data::Medium.new(
        :id               => 'abc_sms',
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
        # :tags       => ['admin', 'night_shift']
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
        # :tags       => ['admin', 'night_shift']
      )
      contact.save

      existing_nr = contact.notification_rules.all.first

      notification_rule = Flapjack::Data::NotificationRule.new(
        :id                 => '05983623-fcef-42da-af44-ed6990b500fa',
        :time_restrictions  => [],
        # :warning_media      => ["email"],
        # :critical_media     => ["sms", "email"],
        # :warning_blackhole  => false,
        # :critical_blackhole => false
      )
      notification_rule.save
      contact.notification_rules << notification_rule
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
        # :tags       => ['admin', 'night_shift']
      )
      contact.save

      existing_nr = contact.notification_rules.all.first

      notification_rule = Flapjack::Data::NotificationRule.new(
        :id                 => '05983623-fcef-42da-af44-ed6990b500fa',
        :time_restrictions  => [],
        # :warning_media      => ["email"],
        # :critical_media     => ["sms", "email"],
        # :warning_blackhole  => false,
        # :critical_blackhole => false
      )
      notification_rule.save
      contact.notification_rules << notification_rule
      existing_nr.destroy

      notification_rule_2 = Flapjack::Data::NotificationRule.new(
        :id                 => '20f182fc-6e32-4794-9007-97366d162c51',
        :time_restrictions  => [],
        # :warning_media      => ["email"],
        # :critical_media     => ["sms", "email"],
        # :warning_blackhole  => true,
        # :critical_blackhole => true
      )
      notification_rule_2.save
      contact.notification_rules << notification_rule_2
    end

    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      Flapjack.redis.flushdb
    end
  end

  provider_state "a set of pagerduty credentials 'rstuv' exists" do
    set_up do
      contact = Flapjack::Data::Contact.new(
        :id         => 'abc',
        :first_name => 'Jim',
        :last_name  => 'Smith',
        :email      => 'jims@example.com',
        :timezone   => 'UTC',
        # :tags       => ['admin', 'night_shift']
      )
      contact.save

      pdc = Flapjack::Data::PagerdutyCredentials.new(
        :id          => 'rstuv',
        :service_key => 'abc',
        :subdomain   => 'def',
        :username    => 'ghi',
        :password    => 'jkl',
      )
      pdc.save
      contact.pagerduty_credentials = pdc
    end

    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      Flapjack.redis.flushdb
    end
  end

  provider_state "two sets of pagerduty credentials 'rstuv' and 'wxyza' exist" do
    set_up do
      contact = Flapjack::Data::Contact.new(
        :id         => 'abc',
        :first_name => 'Jim',
        :last_name  => 'Smith',
        :email      => 'jims@example.com',
        :timezone   => 'UTC',
        # :tags       => ['admin', 'night_shift']
      )
      contact.save

      pdc = Flapjack::Data::PagerdutyCredentials.new(
        :id          => 'rstuv',
        :service_key => 'abc',
        :subdomain   => 'def',
        :username    => 'ghi',
        :password    => 'jkl',
      )
      pdc.save
      contact.pagerduty_credentials = pdc

      contact_2 = Flapjack::Data::Contact.new(
        :id         => '872',
        :first_name => 'John',
        :last_name  => 'Smith',
        :email      => 'jsmith@example.com',
      )
      contact_2.save

      pdc_2 = Flapjack::Data::PagerdutyCredentials.new(
        :id          => 'wxyza',
        :service_key => 'mno',
        :subdomain   => 'pqr',
        :username    => 'stu',
        :password    => 'vwx',
      )
      pdc_2.save
      contact_2.pagerduty_credentials = pdc_2
    end

    tear_down do
      Flapjack::Gateways::JSONAPI.instance_variable_get('@logger').messages.clear
      Flapjack.redis.flushdb
    end
  end

end