require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::EntityMethods', :sinatra => true, :logger => true do

  include_context "jsonapi"

  let(:backend) { double(Sandstorm::Backends::Base) }

  let(:entity)        { double(Flapjack::Data::Entity, :id => '126') }
  let(:check)         { double(Flapjack::Data::Check, :id => '457') }
  let(:entity_data)   {
    {:id      => entity.id,
     :name    => 'www.example.com',
     :enabled => false,
     :tags    => []
    }
   }

  it "creates an entity" do
    expect(Flapjack::Data::Entity).to receive(:backend).and_return(backend)
    expect(backend).to receive(:lock).with(Flapjack::Data::Entity).and_yield

    expect(Flapjack::Data::Entity).to receive(:exists?).with(entity.id).and_return(false)

    expect(entity).to receive(:invalid?).and_return(false)
    expect(entity).to receive(:save).and_return(true)
    expect(Flapjack::Data::Entity).to receive(:new).
      with(entity_data).and_return(entity)

    post "/entities", {:entities => [entity_data]}.to_json, jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq([entity.id].to_json)
  end

  it "does not create an entity if the data is improperly formatted" do
    expect(Flapjack::Data::Entity).to receive(:backend).and_return(backend)
    expect(backend).to receive(:lock).with(Flapjack::Data::Entity).and_yield

    expect(Flapjack::Data::Entity).not_to receive(:exists?)

    errors = double('errors', :full_messages => ['err'])
    expect(entity).to receive(:errors).and_return(errors)

    expect(entity).to receive(:invalid?).and_return(true)
    expect(entity).not_to receive(:save)
    expect(Flapjack::Data::Entity).to receive(:new).and_return(entity)

    post "/entities", {:entities => [{'silly' => 'sausage'}]}.to_json, jsonapi_post_env
    expect(last_response.status).to eq(403)
  end

  it "retrieves all entities" do
    expect(Flapjack::Data::Entity).to receive(:associated_ids_for_contacts).
      with([entity.id]).and_return({})
    expect(Flapjack::Data::Entity).to receive(:associated_ids_for_checks).
      with([entity.id]).and_return({})
    expect(entity).to receive(:as_json).and_return(entity_data)
    all_entities = double('all_entities', :all => [entity])
    expect(Flapjack::Data::Entity).to receive(:intersect).
      with(:enabled => nil).and_return(all_entities)

    get '/entities'
    expect(last_response).to be_ok
    expect(last_response.body).to eq({:entities => [entity_data]}.to_json)
  end

  it "retrieves one entity" do
    expect(Flapjack::Data::Entity).to receive(:associated_ids_for_contacts).
      with([entity.id]).and_return({})
    expect(Flapjack::Data::Entity).to receive(:associated_ids_for_checks).
      with([entity.id]).and_return({})
    expect(entity).to receive(:as_json).and_return(entity_data)
    expect(Flapjack::Data::Entity).to receive(:find_by_ids!).
      with(entity.id).and_return([entity])

    get "/entities/#{entity.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq({:entities => [entity_data]}.to_json)
  end

  it "retrieves several entities" do
    entity_2 = double(Flapjack::Data::Entity, :id => '5678')
    entity_data_2 = {'name' => 'www.example2.com'}

    expect(Flapjack::Data::Entity).to receive(:associated_ids_for_contacts).
      with([entity.id, entity_2.id]).and_return({})
    expect(Flapjack::Data::Entity).to receive(:associated_ids_for_checks).
      with([entity.id, entity_2.id]).and_return({})
    expect(entity).to receive(:as_json).and_return(entity_data)
    expect(entity_2).to receive(:as_json).and_return(entity_data_2)
    expect(Flapjack::Data::Entity).to receive(:find_by_ids!).
      with(entity.id, entity_2.id).and_return([entity, entity_2])

    get "/entities/#{entity.id},#{entity_2.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq({:entities => [entity_data, entity_data_2]}.to_json)
  end

  it "updates an entity" do
    expect(Flapjack::Data::Entity).to receive(:find_by_ids!).
      with(entity.id).and_return([entity])

    expect(entity).to receive(:enabled=).with(true)
    expect(entity).to receive(:save).and_return(true)

    patch "/entities/#{entity.id}",
      [{:op => 'replace', :path => '/entities/0/enabled', :value => true}].to_json,
      jsonapi_patch_env
    expect(last_response.status).to eq(204)
  end


  it "creates an acknowledgement for all checks on an entity" do
    expect(Flapjack::Data::Check).to receive(:find_by_ids!).
      with(check.id).and_return([check])

    expect(Flapjack::Data::Event).to receive(:create_acknowledgement).
      with('events', check, :duration => (4 * 60 * 60))

    expect(Flapjack::Data::Entity).to receive(:associated_ids_for_checks).
      with([entity.id]).and_return(entity.id => [check.id])

    post "/unscheduled_maintenances/entities/#{entity.id}", {}, jsonapi_post_env
    expect(last_response.status).to eq(204)
  end

  it "ends an unscheduled maintenance period for all checks on an entity" do
    end_time = Time.now + (60 * 60) # an hour from now
    expect(check).to receive(:clear_unscheduled_maintenance).with(end_time.to_i)

    expect(Flapjack::Data::Check).to receive(:find_by_ids!).
      with(check.id).and_return([check])

    expect(Flapjack::Data::Entity).to receive(:associated_ids_for_checks).
      with([entity.id]).and_return(entity.id => [check.id])

    patch "/unscheduled_maintenances/entities/#{entity.id}",
      [{:op => 'replace', :path => '/unscheduled_maintenances/0/end_time', :value => end_time.iso8601}].to_json,
      jsonapi_patch_env
    expect(last_response.status).to eq(204)
  end

  it "creates a scheduled maintenance period for all checks on an entity" do
    start = Time.now + (60 * 60) # an hour from now
    duration = (2 * 60 * 60)     # two hours

    expect(Flapjack::Data::Check).to receive(:backend).and_return(backend)
    expect(backend).to receive(:lock).
      with(Flapjack::Data::Check, Flapjack::Data::ScheduledMaintenance).and_yield

    expect(Flapjack::Data::Check).to receive(:find_by_ids!).
      with(check.id).and_return([check])

    sched_maint = double(Flapjack::Data::ScheduledMaintenance)
    expect(sched_maint).to receive(:invalid?).and_return(false)
    expect(sched_maint).to receive(:save).and_return(true)
    expect(check).to receive(:add_scheduled_maintenance).with(sched_maint)
    expect(Flapjack::Data::ScheduledMaintenance).to receive(:new).
      with(:start_time => start.getutc.to_i,
           :end_time => start.getutc.to_i + duration,
           :summary => 'test').
      and_return(sched_maint)

    expect(Flapjack::Data::Entity).to receive(:associated_ids_for_checks).
      with([entity.id]).and_return(entity.id => [check.id])

    post "/scheduled_maintenances/entities/#{entity.id}",
      {:scheduled_maintenances => [{:start_time => start.iso8601, :summary => 'test', :duration => duration}]}.to_json,
      jsonapi_post_env
    expect(last_response.status).to eq(204)
  end

  it "doesn't create a scheduled maintenance period for all checks on an entity if the start time isn't passed" do
    duration = (2 * 60 * 60)     # two hours

    expect(Flapjack::Data::Entity).to receive(:associated_ids_for_checks).
      with([entity.id]).and_return(entity.id => [check.id])

    post "/scheduled_maintenances/entities/#{entity.id}",
      {:summary => 'test', :duration => duration}.to_json, jsonapi_post_env
    expect(last_response.status).to eq(403)
  end

  it "deletes a scheduled maintenance period for all checks on an entity" do
    start_time = Time.now + (60 * 60) # an hour from now

    sched_maint = double(Flapjack::Data::ScheduledMaintenance)
    sched_maints = double('sched_maints', :all => [sched_maint])
    sm_range = double('sm_range')
    expect(sm_range).to receive(:intersect_range).
      with(start_time.to_i, start_time.to_i, :by_score => true).
      and_return(sched_maints)

    expect(check).to receive(:scheduled_maintenances_by_start).and_return(sm_range)
    expect(check).to receive(:end_scheduled_maintenance).with(sched_maint, an_instance_of(Time))

    expect(Flapjack::Data::Check).to receive(:find_by_ids!).
      with(check.id).and_return([check])

    expect(Flapjack::Data::Entity).to receive(:associated_ids_for_checks).
      with([entity.id]).and_return(entity.id => [check.id])

    delete "/scheduled_maintenances/entities/#{entity.id}",
      :start_time => start_time.iso8601
    expect(last_response.status).to eq(204)
  end

  it "doesn't delete a scheduled maintenance period for all checks on an entityif the start time isn't passed" do
    expect(check).not_to receive(:end_scheduled_maintenance)

    delete "/scheduled_maintenances/entities/#{entity.id}"
    expect(last_response.status).to eq(403)
  end

  it "deletes scheduled maintenance periods for all checks on multiple entities" do
    start_time = Time.now + (60 * 60) # an hour from now

    check_2 = double(Flapjack::Data::Check, :id => '9012')

    sched_maint = double(Flapjack::Data::ScheduledMaintenance)
    sched_maints = double('sched_maints', :all => [sched_maint])
    sm_range = double('sm_range')
    expect(sm_range).to receive(:intersect_range).
      with(start_time.to_i, start_time.to_i, :by_score => true).
      and_return(sched_maints)

    sched_maint_2 = double(Flapjack::Data::ScheduledMaintenance)
    sched_maints_2 = double('sched_maints', :all => [sched_maint_2])
    sm_range_2 = double('sm_range')
    expect(sm_range_2).to receive(:intersect_range).
      with(start_time.to_i, start_time.to_i, :by_score => true).
      and_return(sched_maints_2)

    expect(check).to receive(:scheduled_maintenances_by_start).and_return(sm_range)
    expect(check).to receive(:end_scheduled_maintenance).with(sched_maint, an_instance_of(Time))

    expect(check_2).to receive(:scheduled_maintenances_by_start).and_return(sm_range_2)
    expect(check_2).to receive(:end_scheduled_maintenance).with(sched_maint_2, an_instance_of(Time))

    expect(Flapjack::Data::Check).to receive(:find_by_ids!).
      with(check.id, check_2.id).and_return([check, check_2])

    expect(Flapjack::Data::Entity).to receive(:associated_ids_for_checks).
      with([entity.id]).and_return(entity.id => [check.id, check_2.id])

    delete "/scheduled_maintenances/entities/#{entity.id}",
      :start_time => start_time.iso8601
    expect(last_response.status).to eq(204)
  end

  it "creates a test notification event for all checks on an entity" do
    expect(Flapjack::Data::Check).to receive(:find_by_ids!).
      with(check.id).and_return([check])

    expect(check).to receive(:entity_name).and_return('www.example.com')

    expect(Flapjack::Data::Event).to receive(:test_notifications).
      with('events', check, an_instance_of(Hash))

    expect(Flapjack::Data::Entity).to receive(:associated_ids_for_checks).
      with([entity.id]).and_return(entity.id => [check.id])

    post "/test_notifications/entities/#{entity.id}"
    expect(last_response.status).to eq(204)
  end

end

  #   it "creates entities from a submitted list" do
  #     entities = {'entities' =>
  #       [
  #        {"id" => "10001",
  #         "name" => "clientx-app-01",
  #         "contacts" => ["0362","0363","0364"]
  #        },
  #        {"id" => "10002",
  #         "name" => "clientx-app-02",
  #         "contacts" => ["0362"]
  #        }
  #       ]
  #     }

  #     expect(Flapjack::Data::Entity).to receive(:intersect).
  #       with(:name => 'clientx-app-01').and_return(no_entities)
  #     expect(Flapjack::Data::Entity).to receive(:intersect).
  #       with(:name => 'clientx-app-02').and_return(no_entities)

  #     expect(Flapjack::Data::Contact).to receive(:find_by_id).exactly(4).times.and_return(nil)

  #     expect(entity).to receive(:valid?).and_return(true)
  #     expect(entity).to receive(:save).and_return(true)
  #     expect(entity).to receive(:id).and_return('10001')

  #     entity_2 = double(Flapjack::Data::Entity)
  #     expect(entity_2).to receive(:valid?).and_return(true)
  #     expect(entity_2).to receive(:save).and_return(true)
  #     expect(entity_2).to receive(:id).and_return('10002')

  #     expect(Flapjack::Data::Entity).to receive(:new).
  #       with(:id => '10001', :name => 'clientx-app-01', :enabled => false).
  #       and_return(entity)
  #     expect(Flapjack::Data::Entity).to receive(:new).
  #       with(:id => '10002', :name => 'clientx-app-02', :enabled => false).
  #       and_return(entity_2)

  #     post "/entities", entities.to_json, {'CONTENT_TYPE' => 'application/json'}
  #     expect(last_response.status).to eq(204)
  #   end

  #   it "does not create entities if the data is improperly formatted" do
  #     expect(Flapjack::Data::Entity).not_to receive(:new)

  #     post "/entities", {'entities' => ["Hello", "there"]}.to_json,
  #       {'CONTENT_TYPE' => 'application/json'}
  #     expect(last_response.status).to eq(403)
  #   end

  # end
