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

  provider_state "checks 'www.example.com:SSH' and 'www.example.com:PING' exist" do
    set_up do
      redis = Flapjack::Gateways::JSONAPI.instance_variable_get('@redis')

      entity_data = {'id' => '1234', 'name' => 'www.example.com'}
      Flapjack::Data::Entity.add(entity_data, :redis => redis)
      check_data = {'entity_id' => '1234', 'name' => 'SSH'}
      Flapjack::Data::EntityCheck.add(check_data, :redis => redis)
      check_data_2 = {'entity_id' => '1234', 'name' => 'PING'}
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

end