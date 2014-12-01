require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::TestNotifications', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:check)   { double(Flapjack::Data::Check, :id => check_data[:id])   }
  let(:check_2) { double(Flapjack::Data::Check, :id => check_2_data[:id]) }

  it "creates a test notification for a check" do
    expect(Flapjack::Data::Check).to receive(:find_by_ids!).
      with(check.id).and_return([check])

    expect(Flapjack::Data::Event).to receive(:test_notifications).
      with('events', [check], an_instance_of(Hash))

    post "/test_notifications",
      Flapjack.dump_json(:test_notifications => notification_data.merge(:links => {:checks => [check.id]})),
      jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json(:test_notifications =>
      notification_data.merge(:links => {:checks => [check.id]})
    ))
  end

  it 'creates test notifications for multiple checks' do
    expect(Flapjack::Data::Check).to receive(:find_by_ids!).
      with(check.id, check_2.id).and_return([check, check_2])

    expect(Flapjack::Data::Event).to receive(:test_notifications).
      with('events', [check, check_2], an_instance_of(Hash))

    post "/test_notifications",
      Flapjack.dump_json(:test_notifications => notification_data.merge(:links => {:checks => [check.id, check_2.id]})),
      jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json(:test_notifications =>
      notification_data.merge(:links => {:checks => [check.id, check_2.id]})
    ))
  end

  it 'creates multiple test notifications for a check' do
    expect(Flapjack::Data::Check).to receive(:find_by_ids!).
      with(check.id).twice.and_return([check])

    expect(Flapjack::Data::Event).to receive(:test_notifications).
      with('events', [check], an_instance_of(Hash)).twice

    post "/test_notifications",
      Flapjack.dump_json(:test_notifications => [
        notification_data.merge(:links => {:checks => [check.id]}),
        notification_2_data.merge(:links => {:checks => [check.id]})
      ]),
      jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json(:test_notifications => [
      notification_data.merge(:links => {:checks => [check.id]}),
      notification_2_data.merge(:links => {:checks => [check.id]})
    ]))
  end

  it 'creates multiple test notifications for multiple checks' do
    expect(Flapjack::Data::Check).to receive(:find_by_ids!).
      with(check.id, check_2.id).twice.and_return([check, check_2])

    expect(Flapjack::Data::Event).to receive(:test_notifications).
      with('events', [check, check_2], an_instance_of(Hash)).twice

    post "/test_notifications",
      Flapjack.dump_json(:test_notifications => [
        notification_data.merge(:links => {:checks => [check.id, check_2.id]}),
        notification_2_data.merge(:links => {:checks => [check.id, check_2.id]})
      ]),
      jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json(:test_notifications => [
      notification_data.merge(:links => {:checks => [check.id, check_2.id]}),
      notification_2_data.merge(:links => {:checks => [check.id, check_2.id]})
    ]))
  end

end
