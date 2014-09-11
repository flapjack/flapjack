require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::CheckMethods', :sinatra => true, :logger => true do

  include_context "jsonapi"

  let(:entity)          { double(Flapjack::Data::Entity) }
  let(:entity_check)    { double(Flapjack::Data::EntityCheck) }

  let(:entity_name)     { 'www.example.net'}
  let(:check)           { 'ping' }
  let(:check_esc)       { URI.escape(entity_name + ':' + check) }

  let(:check_presenter) { double(Flapjack::Gateways::JSONAPI::CheckPresenter) }

  let(:check_data)      { {'entity_name' => 'www.example.com', 'name' => 'PING' } }

  it "retrieves all checks" do
    expect(entity).to receive(:id).and_return('23')
    expect(entity).to receive(:name).twice.and_return('www.example.net')

    expect(entity_check).to receive(:entity).twice.and_return(entity)
    expect(entity_check).to receive(:check).twice.and_return('PING')
    expect(entity_check).to receive(:to_jsonapi).and_return(check_data.to_json)
    expect(Flapjack::Data::EntityCheck).to receive(:for_event_id).
      with('www.example.net:PING', :logger => @logger, :redis => redis).
      and_return(entity_check)
    expect(Flapjack::Data::EntityCheck).to receive(:find_current_names).
      with(:redis => redis).and_return(['www.example.net:PING'])

    aget '/checks'
    expect(last_response).to be_ok
    expect(last_response.body).to eq({:checks => [check_data]}.to_json)
  end

  it "retrieves one check" do
    expect(entity).to receive(:id).and_return('23')
    expect(entity).to receive(:name).twice.and_return('www.example.net')

    expect(entity_check).to receive(:entity).twice.and_return(entity)
    expect(entity_check).to receive(:check).twice.and_return('PING')
    expect(entity_check).to receive(:to_jsonapi).and_return(check_data.to_json)
    expect(Flapjack::Data::EntityCheck).to receive(:for_event_id).
      with('www.example.com:PING', :logger => @logger, :redis => redis).
      and_return(entity_check)

    aget '/checks/www.example.com:PING'
    expect(last_response).to be_ok
    expect(last_response.body).to eq({:checks => [check_data]}.to_json)
  end

  it "retrieves several entities" do
    entity_check_2 = double(Flapjack::Data::EntityCheck)
    check_data_2 = {'name'        => 'SSH',
                    'entity_name' => 'www.example.com'}

    expect(entity).to receive(:id).twice.and_return('23')
    expect(entity).to receive(:name).exactly(4).times.and_return('www.example.net')

    expect(entity_check).to receive(:entity).twice.and_return(entity)
    expect(entity_check).to receive(:check).twice.and_return('PING')
    expect(entity_check).to receive(:to_jsonapi).and_return(check_data.to_json)
    expect(Flapjack::Data::EntityCheck).to receive(:for_event_id).
      with('www.example.com:PING', :logger => @logger, :redis => redis).
      and_return(entity_check)

    expect(entity_check_2).to receive(:entity).twice.and_return(entity)
    expect(entity_check_2).to receive(:check).twice.and_return('SSH')
    expect(entity_check_2).to receive(:to_jsonapi).and_return(check_data_2.to_json)
    expect(Flapjack::Data::EntityCheck).to receive(:for_event_id).
      with('www.example.com:SSH', :logger => @logger, :redis => redis).
      and_return(entity_check_2)

    aget '/checks/www.example.com:PING,www.example.com:SSH'
    expect(last_response).to be_ok
    expect(last_response.body).to eq({:checks => [check_data, check_data_2]}.to_json)
  end

  it "creates checks from a submitted list" do
    checks = {'checks' =>
      [
       {"entity_id" => "10001",
        "name" => "PING"
       },
       {"entity_id" => "10001",
        "name" => "SSH"
       }
      ]
    }

    entity_check_2 = double(Flapjack::Data::EntityCheck)
    expect(entity).to receive(:name).twice.and_return('example.com')

    expect(entity_check).to receive(:entity).and_return(entity)
    expect(entity_check_2).to receive(:entity).and_return(entity)

    expect(entity_check).to receive(:check).and_return('PING')
    expect(entity_check_2).to receive(:check).and_return('SSH')

    expect(Flapjack::Data::EntityCheck).to receive(:add).twice.
      and_return(entity_check, entity_check_2)

    apost "/checks", checks.to_json, jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.headers['Location']).to eq("http://example.org/checks/example.com:PING,example.com:SSH")
    expect(last_response.body).to eq('["example.com:PING","example.com:SSH"]')
  end

  it 'disables a check' do
    expect(Flapjack::Data::Entity).to receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)
    expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
      with(entity, check, :redis => redis).and_return(entity_check)

    expect(entity_check).to receive(:disable!)

    apatch "/checks/#{check_esc}",
      [{:op => 'replace', :path => '/checks/0/enabled', :value => false}].to_json,
      jsonapi_patch_env
    expect(last_response.status).to eq(204)
  end

  it "sets tags on a check" do
    expect(Flapjack::Data::Entity).to receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)
    expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
      with(entity, check, :redis => redis).and_return(entity_check)

    expect(entity_check).to receive(:update).
      with('tags' => ['database', 'virtualised'])

    apatch "/checks/#{check_esc}",
      [{:op => 'replace', :path => '/checks/0/tags', :value => ['database', 'virtualised']}].to_json,
      jsonapi_patch_env
    expect(last_response.status).to eq(204)
  end

  it "creates an acknowledgement for an entity check" do
    expect(Flapjack::Data::Entity).to receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)
    expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
      with(entity, check, :redis => redis).and_return(entity_check)

    expect(entity_check).to receive(:entity_name).and_return(entity_name)
    expect(entity_check).to receive(:check).and_return(check)

    expect(Flapjack::Data::Event).to receive(:create_acknowledgement).
      with(entity_name, check, :redis => redis, :duration => (4 * 60 * 60))

    apost "/unscheduled_maintenances/checks/#{check_esc}", {}, jsonapi_post_env
    expect(last_response.status).to eq(204)
  end

  it "ends an unscheduled maintenance period for an entity check" do
    end_time = Time.now + (60 * 60) # an hour from now
    expect(entity_check).to receive(:end_unscheduled_maintenance).with(end_time.to_i)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
      with(entity, check, :redis => redis).and_return(entity_check)

    expect(Flapjack::Data::Entity).to receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    apatch "/unscheduled_maintenances/checks/#{check_esc}",
      [{:op => 'replace', :path => '/unscheduled_maintenances/0/end_time', :value => end_time.iso8601}].to_json,
      jsonapi_patch_env
    expect(last_response.status).to eq(204)
  end

  it "ends an unscheduled maintenance period for an entity check with a / in the check name" do
    end_time = Time.now + (60 * 60) # an hour from now
    expect(entity_check).to receive(:end_unscheduled_maintenance).with(end_time.to_i)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
      with(entity, 'Disk/Memory Usage', :redis => redis).and_return(entity_check)

    expect(Flapjack::Data::Entity).to receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    apatch "/unscheduled_maintenances/checks/#{URI.escape(entity_name + ':Disk/Memory Usage')}",
      [{:op => 'replace', :path => '/unscheduled_maintenances/0/end_time', :value => end_time.iso8601}].to_json,
      jsonapi_patch_env
    expect(last_response.status).to eq(204)
  end

  it "creates a scheduled maintenance period for an entity check" do
    start = Time.now + (60 * 60) # an hour from now
    duration = (2 * 60 * 60)     # two hours

    expect(Flapjack::Data::Entity).to receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)
    expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
      with(entity, check, :redis => redis).and_return(entity_check)
    expect(entity_check).to receive(:create_scheduled_maintenance).
      with(start.getutc.to_i, duration, :summary => 'test')

    apost "/scheduled_maintenances/checks/#{check_esc}",
      {:scheduled_maintenances => [{:start_time => start.iso8601, :summary => 'test', :duration => duration}]}.to_json,
      jsonapi_post_env
    expect(last_response.status).to eq(204)
  end

  it "doesn't create a scheduled maintenance period for an entity check if the start time isn't passed" do
    duration = (2 * 60 * 60)     # two hours

    apost "/scheduled_maintenances/checks/#{check_esc}",
      {:summary => 'test', :duration => duration}.to_json, jsonapi_post_env
    expect(last_response.status).to eq(403)
  end

  it "deletes a scheduled maintenance period for an entity check" do
    start_time = Time.now + (60 * 60) # an hour from now
    expect(entity_check).to receive(:end_scheduled_maintenance).with(start_time.to_i)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
      with(entity, check, :redis => redis).and_return(entity_check)

    expect(Flapjack::Data::Entity).to receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    adelete "/scheduled_maintenances/checks/#{check_esc}",
      :start_time => start_time.iso8601
    expect(last_response.status).to eq(204)
  end

  it "doesn't delete a scheduled maintenance period if the start time isn't passed" do
    expect(entity_check).not_to receive(:end_scheduled_maintenance)

    adelete "/scheduled_maintenances/checks/#{check_esc}"
    expect(last_response.status).to eq(403)
  end

  it "deletes scheduled maintenance periods for multiple entity checks" do
    start_time = Time.now + (60 * 60) # an hour from now

    entity_check_2 = double(Flapjack::Data::EntityCheck)

    expect(entity_check).to receive(:end_scheduled_maintenance).with(start_time.to_i)
    expect(entity_check_2).to receive(:end_scheduled_maintenance).with(start_time.to_i)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
      with(entity, check, :redis => redis).and_return(entity_check)
    expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
      with(entity, 'foo', :redis => redis).and_return(entity_check_2)

    expect(Flapjack::Data::Entity).to receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    adelete "/scheduled_maintenances/checks/#{check_esc},#{entity_name}:foo",
      :start_time => start_time.iso8601
    expect(last_response.status).to eq(204)
  end

  it "creates a test notification event for a check on an entity" do
    expect(Flapjack::Data::Entity).to receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)
    expect(entity).to receive(:name).and_return(entity_name)
    expect(entity_check).to receive(:entity).and_return(entity)
    expect(entity_check).to receive(:entity_name).and_return(entity_name)
    expect(entity_check).to receive(:check).and_return(check)
    expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
      with(entity, check, :redis => redis).and_return(entity_check)

    expect(Flapjack::Data::Event).to receive(:test_notifications).
      with(entity_name, check, hash_including(:redis => redis))

    apost "/test_notifications/checks/#{check_esc}"
    expect(last_response.status).to eq(204)
  end

end
