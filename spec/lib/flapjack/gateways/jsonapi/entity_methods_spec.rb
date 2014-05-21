require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::EntityMethods', :sinatra => true, :logger => true do

  include_context "jsonapi"

  let(:entity)          { double(Flapjack::Data::Entity) }
  let(:entity_check)    { double(Flapjack::Data::EntityCheck) }
  let(:entity_core)     { {'id'   => '1234', 'name' => 'www.example.com'} }

  let(:entity_id)       { '457' }
  let(:entity_name)     { 'www.example.net'}
  let(:entity_name_esc) { URI.escape(entity_name) }
  let(:check)           { 'ping' }

  let(:check_presenter) { double(Flapjack::Gateways::JSONAPI::CheckPresenter) }

  it "retrieves all entities" do
    expect(entity).to receive(:id).exactly(4).times.and_return(entity_core['id'])

    expect(Flapjack::Data::Entity).to receive(:contact_ids_for).
      with([entity_core['id']], :redis => redis).and_return({})
    expect(entity).to receive(:to_jsonapi).and_return(entity_core.to_json)
    expect(Flapjack::Data::Entity).to receive(:all).with(:redis => redis).
      and_return([entity])

    aget '/entities'
    expect(last_response).to be_ok
    expect(last_response.body).to eq({:entities => [entity_core]}.to_json)
  end

  it "skips entities without ids when getting all" do
    idless_entity = double(Flapjack::Data::Entity, :id => '')

    expect(entity).to receive(:id).exactly(4).times.and_return(entity_core['id'])
    expect(Flapjack::Data::Entity).to receive(:contact_ids_for).
      with([entity_core['id']], :redis => redis).and_return({})
    expect(entity).to receive(:to_jsonapi).and_return(entity_core.to_json)
    expect(idless_entity).not_to receive(:to_jsonapi)
    expect(Flapjack::Data::Entity).to receive(:all).with(:redis => redis).
      and_return([entity, idless_entity])

    aget '/entities'
    expect(last_response).to be_ok
    expect(last_response.body).to eq({:entities => [entity_core]}.to_json)
  end

  it "retrieves one entity" do
    entity_core = {'id'   => '1234',
                   'name' => 'www.example.com'}
    expect(entity).to receive(:id).twice.and_return('1234')

    expect(Flapjack::Data::Entity).to receive(:contact_ids_for).
      with(['1234'], :redis => redis).and_return({})
    expect(entity).to receive(:to_jsonapi).and_return(entity_core.to_json)
    expect(Flapjack::Data::Entity).to receive(:find_by_id).
      with('1234', :logger => @logger, :redis => redis).
      and_return(entity)

    aget '/entities/1234'
    expect(last_response).to be_ok
    expect(last_response.body).to eq({:entities => [entity_core]}.to_json)
  end

  it "retrieves several entities" do
    entity_2 = double(Flapjack::Data::Entity)
    entity_core = {'id'   => '1234',
                   'name' => 'www.example.com'}
    entity_core_2 = {'id'   => '5678',
                   'name' => 'www.example2.com'}

    expect(Flapjack::Data::Entity).to receive(:contact_ids_for).
      with(['1234', '5678'], :redis => redis).and_return({})

    expect(entity).to receive(:id).twice.and_return('1234')
    expect(entity_2).to receive(:id).twice.and_return('5678')

    expect(entity).to receive(:to_jsonapi).and_return(entity_core.to_json)
    expect(entity_2).to receive(:to_jsonapi).and_return(entity_core_2.to_json)

    expect(Flapjack::Data::Entity).to receive(:find_by_id).
      with('1234', :logger => @logger, :redis => redis).
      and_return(entity)
    expect(Flapjack::Data::Entity).to receive(:find_by_id).
      with('5678', :logger => @logger, :redis => redis).
      and_return(entity_2)

    aget '/entities/1234,5678'
    expect(last_response).to be_ok
    expect(last_response.body).to eq({:entities => [entity_core, entity_core_2]}.to_json)
  end

  it "creates entities from a submitted list" do
    entities = {'entities' =>
      [
       {"id" => "10001",
        "name" => "clientx-app-01",
        "contacts" => ["0362","0363","0364"]
       },
       {"id" => "10002",
        "name" => "clientx-app-02",
        "contacts" => ["0362"]
       }
      ]
    }
    expect(Flapjack::Data::Entity).to receive(:add).twice

    apost "/entities", entities.to_json, jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.headers['Location']).to eq("http://example.org/entities/10001,10002")
    expect(last_response.body).to eq('["10001","10002"]')
  end

  it "does not create entities if the data is improperly formatted" do
    expect(Flapjack::Data::Entity).not_to receive(:add)

    apost "/entities", {'entities' => ["Hello", "there"]}.to_json, jsonapi_post_env
    expect(last_response.status).to eq(403)
  end

  it "does not create entities if they don't contain an id" do
    entities = {'entities' =>
      [
       {"id" => "10001",
        "name" => "clientx-app-01",
        "contacts" => ["0362","0363","0364"]
       },
       {"name" => "clientx-app-02",
        "contacts" => ["0362"]
       }
      ]
    }
    expect(Flapjack::Data::Entity).not_to receive(:add)

    apost "/entities", entities.to_json, jsonapi_post_env
    expect(last_response.status).to eq(403)
  end

  it "updates an entity" do
    contact = double(Flapjack::Data::Contact)
    expect(contact).to receive(:add_entity).with(entity)
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('32', :redis => redis).and_return(contact)

    expect(Flapjack::Data::Entity).to receive(:find_by_id).
      with('1234', :redis => redis).and_return(entity)

    apatch "/entities/1234",
      [{:op => 'add', :path => '/entities/0/links/contacts/-', :value => '32'}].to_json,
      jsonapi_patch_env
    expect(last_response.status).to eq(204)
  end

  it "creates acknowledgements for all checks on an entity" do
    expect(entity).to receive(:check_list).and_return([check])
    expect(Flapjack::Data::Entity).to receive(:find_by_id).
      with(entity_id, :redis => redis).and_return(entity)
    expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
      with(entity, check, :redis => redis).and_return(entity_check)

    expect(entity_check).to receive(:entity_name).and_return(entity_name)
    expect(entity_check).to receive(:check).and_return(check)

    expect(Flapjack::Data::Event).to receive(:create_acknowledgement).
      with(entity_name, check, :duration => (4 * 60 * 60), :redis => redis)

    apost "/unscheduled_maintenances/entities/#{entity_id}"
    expect(last_response.status).to eq(204)
  end

  it "ends unscheduled maintenance periods for all checks on an entity" do
    end_time = Time.now + (60 * 60) # an hour from now
    expect(entity_check).to receive(:end_unscheduled_maintenance).with(end_time.to_i)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
      with(entity, check, :redis => redis).and_return(entity_check)

    expect(entity).to receive(:check_list).and_return([check])
    expect(Flapjack::Data::Entity).to receive(:find_by_id).
      with(entity_id, :redis => redis).and_return(entity)

    apatch "/unscheduled_maintenances/entities/#{entity_id}",
      [{:op => 'replace', :path => '/unscheduled_maintenances/0/end_time', :value => end_time.iso8601}].to_json,
      jsonapi_patch_env
    expect(last_response.status).to eq(204)
  end

  it "creates scheduled maintenance periods for all checks on an entity" do
    start = Time.now + (60 * 60) # an hour from now
    duration = (2 * 60 * 60)     # two hours

    expect(entity).to receive(:check_list).and_return([check])
    expect(Flapjack::Data::Entity).to receive(:find_by_id).
      with(entity_id, :redis => redis).and_return(entity)
    expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
      with(entity, check, :redis => redis).and_return(entity_check)
    expect(entity_check).to receive(:create_scheduled_maintenance).
      with(start.getutc.to_i, duration, :summary => 'test')

    apost "/scheduled_maintenances/entities/#{entity_id}",
      {:scheduled_maintenances => [{:start_time => start.iso8601, :summary => 'test', :duration => duration}]}.to_json,
      jsonapi_post_env

    expect(last_response.status).to eq(204)
  end

  it "doesn't create scheduled maintenance periods if the start time isn't passed" do
    duration = (2 * 60 * 60)     # two hours

    expect(entity).to receive(:check_list).and_return([check])
    expect(Flapjack::Data::Entity).to receive(:find_by_id).
      with(entity_id, :redis => redis).and_return(entity)
    expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
      with(entity, check, :redis => redis).and_return(entity_check)
    expect(entity_check).not_to receive(:create_scheduled_maintenance)

    apost "/scheduled_maintenances/entities/#{entity_id}",
       {:scheduled_maintenances => [{:summary => 'test', :duration => duration}]}.to_json, jsonapi_post_env
    expect(last_response.status).to eq(403)
  end

  it "deletes scheduled maintenance periods for all checks on an entity" do
    start_time = Time.now + (60 * 60) # an hour from now
    expect(entity_check).to receive(:end_scheduled_maintenance).with(start_time.to_i)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
      with(entity, check, :redis => redis).and_return(entity_check)

    expect(entity).to receive(:check_list).and_return([check])
    expect(Flapjack::Data::Entity).to receive(:find_by_id).
      with(entity_id, :redis => redis).and_return(entity)

    adelete "/scheduled_maintenances/entities/#{entity_id}",
      :start_time => start_time.iso8601
    expect(last_response.status).to eq(204)
  end

  it "doesn't delete scheduled maintenance periods if the start time isn't passed" do
    expect(entity_check).not_to receive(:end_scheduled_maintenance)

    adelete "/scheduled_maintenances/entities/#{entity_id}"
    expect(last_response.status).to eq(403)
  end

  it "deletes scheduled maintenance periods for all checks on a multiple entities" do
    start_time = Time.now + (60 * 60) # an hour from now

    check_2 = 'HOST'
    entity_2 = double(Flapjack::Data::Entity)
    entity_check_2 = double(Flapjack::Data::EntityCheck)

    expect(entity_check).to receive(:end_scheduled_maintenance).with(start_time.to_i)
    expect(entity_check_2).to receive(:end_scheduled_maintenance).with(start_time.to_i)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
      with(entity, check, :redis => redis).and_return(entity_check)
    expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
      with(entity_2, check_2, :redis => redis).and_return(entity_check_2)

    expect(entity).to receive(:check_list).and_return([check])
    expect(Flapjack::Data::Entity).to receive(:find_by_id).
      with(entity_id, :redis => redis).and_return(entity)

    expect(entity_2).to receive(:check_list).and_return([check_2])
    expect(Flapjack::Data::Entity).to receive(:find_by_id).
      with('873', :redis => redis).and_return(entity_2)

    adelete "/scheduled_maintenances/entities/#{entity_id},873",
      :start_time => start_time.iso8601
    expect(last_response.status).to eq(204)
  end

  it "creates test notification events for all checks on an entity" do
    expect(entity).to receive(:check_list).and_return([check, 'foo'])
    expect(entity).to receive(:name).twice.and_return(entity_name)
    expect(Flapjack::Data::Entity).to receive(:find_by_id).
      with(entity_id, :redis => redis).and_return(entity)

    expect(entity_check).to receive(:entity).and_return(entity)
    expect(entity_check).to receive(:entity_name).and_return(entity_name)
    expect(entity_check).to receive(:check).and_return(check)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
      with(entity, check, :redis => redis).and_return(entity_check)

    entity_check_2 = double(Flapjack::Data::EntityCheck)
    expect(entity_check_2).to receive(:entity).and_return(entity)
    expect(entity_check_2).to receive(:entity_name).and_return(entity_name)
    expect(entity_check_2).to receive(:check).and_return('foo')

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
      with(entity, 'foo', :redis => redis).and_return(entity_check_2)

    expect(Flapjack::Data::Event).to receive(:test_notifications).
      with(entity_name, check, hash_including(:redis => redis))

    expect(Flapjack::Data::Event).to receive(:test_notifications).
      with(entity_name, 'foo', hash_including(:redis => redis))

    apost "/test_notifications/entities/#{entity_id}"
    expect(last_response.status).to eq(204)
  end

end
