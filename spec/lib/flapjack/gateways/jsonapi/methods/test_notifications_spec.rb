require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::TestNotifications', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:check)   { double(Flapjack::Data::Check, :id => check_data[:id])   }
  let(:check_2) { double(Flapjack::Data::Check, :id => check_2_data[:id]) }
  let(:checks)  { double('checks') }

  let(:tag)     { double(Flapjack::Data::Tag, :id => tag_data[:name])   }

  it "creates a test notification for a check" do
    expect(check).to receive(:name).and_return(check_data[:name])
    expect(Flapjack::Data::Check).to receive(:find_by_id!).
      with(check.id).and_return(check)

    expect(Flapjack::Data::Event).to receive(:test_notifications).
      with('events', [check], an_instance_of(Hash))

    post "/test_notifications/checks/#{check.id}",
      Flapjack.dump_json(:data => notification_data),
      jsonapi_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data =>
      notification_data
    ))
  end

  it 'creates test notifications for checks linked to a tag' do
    expect(check).to receive(:name).and_return(check_data[:name])
    expect(check_2).to receive(:name).and_return(check_2_data[:name])
    expect(checks).to receive(:map).and_yield(check).and_yield(check_2)
    expect(tag).to receive(:checks).and_return(checks)
    expect(Flapjack::Data::Tag).to receive(:find_by_id!).
      with(tag.id).and_return(tag)

    expect(Flapjack::Data::Event).to receive(:test_notifications).
      with('events', checks, an_instance_of(Hash))

    post "/test_notifications/tags/#{tag.id}",
      Flapjack.dump_json(:data => notification_data),
      jsonapi_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data =>
      notification_data
    ))
  end

  it 'creates multiple test notifications for a check' do
    expect(check).to receive(:name).and_return(check_data[:name])
    expect(Flapjack::Data::Check).to receive(:find_by_id!).
      with(check.id).and_return(check)

    expect(Flapjack::Data::Event).to receive(:test_notifications).
      with('events', [check], an_instance_of(Hash)).twice

    post "/test_notifications/checks/#{check.id}",
      Flapjack.dump_json(:data => [notification_data, notification_2_data]),
      jsonapi_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data =>
      [notification_data, notification_2_data]
    ))
  end

  it 'creates multiple test notifications for checks linked to a tag' do
    expect(check).to receive(:name).and_return(check_data[:name])
    expect(check_2).to receive(:name).and_return(check_2_data[:name])
    expect(checks).to receive(:map).and_yield(check).and_yield(check_2)
    expect(tag).to receive(:checks).and_return(checks)
    expect(Flapjack::Data::Tag).to receive(:find_by_id!).
      with(tag.id).and_return(tag)

    expect(Flapjack::Data::Event).to receive(:test_notifications).
      with('events', checks, an_instance_of(Hash)).twice

    post "/test_notifications/tags/#{tag.id}",
      Flapjack.dump_json(:data => [notification_data, notification_2_data]),
      jsonapi_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data =>
      [notification_data, notification_2_data]
    ))
  end

end
