require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::CheckMethods', :sinatra => true, :logger => true do

  def app
    Flapjack::Gateways::JSONAPI
  end

  let(:entity)          { double(Flapjack::Data::Entity) }
  let(:entity_check)    { double(Flapjack::Data::EntityCheck) }

  let(:entity_name)     { 'www.example.net'}
  let(:entity_name_esc) { URI.escape(entity_name) }
  let(:check)           { 'ping' }

  let(:check_presenter) { double(Flapjack::Gateways::JSONAPI::CheckPresenter) }

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

  it "creates an acknowledgement for an entity check" do
    expect(Flapjack::Data::Entity).to receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)
    expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
      with(entity, check, :redis => redis).and_return(entity_check)

    expect(entity_check).to receive(:entity_name).and_return(entity_name)
    expect(entity_check).to receive(:check).and_return(check)

    expect(Flapjack::Data::Event).to receive(:create_acknowledgement).
      with(entity_name, check, :summary => nil, :duration => (4 * 60 * 60), :redis => redis)

    apost "/unscheduled_maintenances/checks/#{entity_name}:#{check}", {}, jsonapi_env
    expect(last_response.status).to eq(201)
    expect(last_response.headers['Location']).to match(/http:\/\/example.org\/unscheduled_maintenance_report\/checks\/#{entity_name}:#{check}\?start_time=.+/)
  end

  it "ends an unscheduled maintenance period for an entity check" do
    end_time = Time.now + (60 * 60) # an hour from now
    expect(entity_check).to receive(:end_unscheduled_maintenance).with(end_time.to_i)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
      with(entity, check, :redis => redis).and_return(entity_check)

    expect(Flapjack::Data::Entity).to receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    apatch "/unscheduled_maintenances/checks/#{entity_name}:#{check}",
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

    apost "/scheduled_maintenances/checks/#{entity_name}:#{check}",
      {:start_time => start.iso8601, :summary => 'test', :duration => duration}.to_json,
      jsonapi_env
    expect(last_response.status).to eq(201)
    expect(last_response.headers['Location']).to eq("http://example.org/scheduled_maintenance_report/checks/#{entity_name}:#{check}?start_time=#{start.iso8601}")
  end

  it "doesn't create a scheduled maintenance period for an entity check if the start time isn't passed" do
    duration = (2 * 60 * 60)     # two hours

    apost "/scheduled_maintenances/checks/#{entity_name}:#{check}",
      {:summary => 'test', :duration => duration}.to_json, jsonapi_env
    expect(last_response.status).to eq(403)
  end

  it "deletes a scheduled maintenance period for an entity check" do
    start_time = Time.now + (60 * 60) # an hour from now
    expect(entity_check).to receive(:end_scheduled_maintenance).with(start_time.to_i)

    expect(Flapjack::Data::EntityCheck).to receive(:for_entity).
      with(entity, check, :redis => redis).and_return(entity_check)

    expect(Flapjack::Data::Entity).to receive(:find_by_name).
      with(entity_name, :redis => redis).and_return(entity)

    adelete "/scheduled_maintenances/checks/#{entity_name}:#{check}",
      {:start_time => start_time.iso8601}.to_json,
      jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it "doesn't delete a scheduled maintenance period if the start time isn't passed" do
    expect(entity_check).not_to receive(:end_scheduled_maintenance)

    adelete "/scheduled_maintenances/checks/#{entity_name}:#{check}", {},
      jsonapi_env
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

    adelete "/scheduled_maintenances/checks/#{entity_name}:#{check},#{entity_name}:foo",
       {:start_time => start_time.iso8601}.to_json, jsonapi_env
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

    apost "/test_notifications/checks/#{entity_name}:#{check}", {}, jsonapi_env
    expect(last_response.status).to eq(201)
  end

end
