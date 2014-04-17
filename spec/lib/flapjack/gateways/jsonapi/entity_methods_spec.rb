require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::EntityMethods', :sinatra => true, :logger => true do

  def app
    Flapjack::Gateways::JSONAPI
  end

  let(:entity)          { double(Flapjack::Data::Entity) }
  let(:entity_check)    { double(Flapjack::Data::EntityCheck) }

  let(:entity_id)       { '457' }
  let(:entity_name)     { 'www.example.net'}
  let(:entity_name_esc) { URI.escape(entity_name) }
  let(:check)           { 'ping' }

  let(:entity_check_presenter) { double(Flapjack::Gateways::JSONAPI::EntityCheckPresenter) }

  let(:redis)           { double(::Redis) }

  let(:jsonapi_env) {
    {'CONTENT_TYPE' => Flapjack::Gateways::JSONAPI::JSONAPI_MEDIA_TYPE,
     'HTTP_ACCEPT'  => 'application/json; q=0.8, application/vnd.api+json'}
  }

  let(:jsonapi_patch_env) {
    {'CONTENT_TYPE' => Flapjack::Gateways::JSONAPI::JSON_PATCH_MEDIA_TYPE,
     'HTTP_ACCEPT'  => 'application/json; q=0.8, application/vnd.api+json'}
  }

  before(:all) do
    Flapjack::Gateways::JSONAPI.class_eval {
      set :raise_errors, true
    }
  end

  before(:each) do
    expect(Flapjack::RedisPool).to receive(:new).and_return(redis)
    Flapjack::Gateways::JSONAPI.instance_variable_set('@config', {})
    Flapjack::Gateways::JSONAPI.instance_variable_set('@logger', @logger)
    Flapjack::Gateways::JSONAPI.start
  end

  after(:each) do
    if last_response.status >= 200 && last_response.status < 300
      expect(last_response.headers.keys).to include('Access-Control-Allow-Methods')
      expect(last_response.headers['Access-Control-Allow-Origin']).to eq("*")
      unless [201, 204].include?(last_response.status)
        expect(Oj.load(last_response.body)).to be_a(Enumerable)
        expect(last_response.headers['Content-Type']).to eq(Flapjack::Gateways::JSONAPI::JSONAPI_MEDIA_TYPE)
      end
    end
  end

  it "retrieves all entities" do
    entity_core = {'id'   => '1234',
                   'name' => 'www.example.com'}
    expect(entity).to receive(:id).twice.and_return('1234')

    expect(Flapjack::Data::Entity).to receive(:contact_ids_for).
      with(['1234'], :redis => redis).and_return({})
    expect(entity).to receive(:to_jsonapi).and_return(entity_core.to_json)
    expect(Flapjack::Data::Entity).to receive(:all).with(:redis => redis).
      and_return([entity])

    aget '/entities', {}.to_json, jsonapi_env
    expect(last_response).to be_ok
    expect(last_response.body).to eq({:entities => [entity_core]}.to_json)
  end

  it "retrieves one entity"

  it "retrieves a group of entities"

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

    apost "/entities", entities.to_json, jsonapi_env
    expect(last_response.status).to eq(201)
    expect(last_response.headers['Location']).to eq("http://example.org/entities/10001,10002")
    expect(last_response.body).to eq('["10001","10002"]')
  end

  it "does not create entities if the data is improperly formatted" do
    expect(Flapjack::Data::Entity).not_to receive(:add)

    apost "/entities", {'entities' => ["Hello", "there"]}.to_json, jsonapi_env
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

    apost "/entities", entities.to_json, jsonapi_env
    expect(last_response.status).to eq(403)
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
      with(entity_name, check, :summary => nil, :duration => (4 * 60 * 60), :redis => redis)

    apost "/unscheduled_maintenances/entities/#{entity_id}", {}, jsonapi_env
    expect(last_response.status).to eq(201)
    expect(last_response.headers['Location']).to match(/http:\/\/example.org\/unscheduled_maintenance_report\/entities\/#{entity_id}\?start_time=/)
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
      {:start_time => start.iso8601, :summary => 'test', :duration => duration}.to_json,
      jsonapi_env
    expect(last_response.status).to eq(201)
    expect(last_response.headers['Location']).to eq("http://example.org/scheduled_maintenance_report/entities/#{entity_id}?start_time=#{start.iso8601}")
  end

  it "doesn't create scheduled maintenance periods if the start time isn't passed" do
    duration = (2 * 60 * 60)     # two hours

    apost "/scheduled_maintenances/entities/#{entity_id}",
      {:summary => 'test', :duration => duration}.to_json, jsonapi_env
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
      {:start_time => start_time.iso8601}.to_json,
      jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it "doesn't delete scheduled maintenance periods if the start time isn't passed" do
    expect(entity_check).not_to receive(:end_scheduled_maintenance)

    adelete "/scheduled_maintenances/entities/#{entity_id}", {}, jsonapi_env
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
      {:start_time => start_time.iso8601}.to_json, jsonapi_env
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

    apost "/test_notifications/entities/#{entity_id}", {}, jsonapi_env
    expect(last_response.status).to eq(201)
  end

end
