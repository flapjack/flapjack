Pact.provider_states_for "flapjack-diner" do

  provider_state "no entity exists" do
    set_up do
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

end