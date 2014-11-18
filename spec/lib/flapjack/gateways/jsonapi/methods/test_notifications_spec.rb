require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::TestNotifications', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:check)   { double(Flapjack::Data::Check, :id => check_data[:id])   }
  let(:check_2) { double(Flapjack::Data::Check, :id => check_2_data[:id]) }

  let(:summary) { "Testing notifications to everyone interested in #{check_data[:name]}" }
  let(:summary_both) { "Testing notifications to everyone interested in #{check_data[:name]}, #{check_2_data[:name]}" }

  it "creates a test notification for a check" do
    expect(Flapjack::Data::Check).to receive(:find_by_ids!).
      with(check.id).and_return([check])

    expect(check).to receive(:name).and_return(check_data[:name])
    expect(Flapjack::Data::Event).to receive(:test_notifications).
      with('events', [check], an_instance_of(Hash))

    post "/test_notifications/#{check.id}", '', jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json(:test_notifications => [{
      :summary => summary, :links => {:checks => [check.id]}
    }]))
  end

  it 'creates test notifications for multiple checks' do
    expect(Flapjack::Data::Check).to receive(:find_by_ids!).
      with(check.id, check_2.id).and_return([check, check_2])

    expect(check).to receive(:name).and_return(check_data[:name])
    expect(check_2).to receive(:name).and_return(check_2_data[:name])
    expect(Flapjack::Data::Event).to receive(:test_notifications).
      with('events', [check, check_2], an_instance_of(Hash))

    post "/test_notifications/#{check.id},#{check_2.id}", '', jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json(:test_notifications => [{
      :summary => summary_both, :links => {:checks => [check.id, check_2.id]}
    }]))
  end

  it 'creates multiple test notifications for a check' do
    expect(Flapjack::Data::Check).to receive(:find_by_ids!).
      with(check.id).and_return([check])

    expect(check).to receive(:name).twice.and_return(check_data[:name])
    expect(Flapjack::Data::Event).to receive(:test_notifications).
      with('events', [check], an_instance_of(Hash)).twice

    post "/test_notifications/#{check.id}", Flapjack.dump_json(:test_notifications => [
      {}, {}
    ]), jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json(:test_notifications => [{
      :summary => summary, :links => {:checks => [check.id]}
    }, {
      :summary => summary, :links => {:checks => [check.id]}
    }]))
  end

  it 'creates multiple test notifications for multiple checks' do
    expect(Flapjack::Data::Check).to receive(:find_by_ids!).
      with(check.id, check_2.id).and_return([check, check_2])

    expect(check).to receive(:name).twice.and_return(check_data[:name])
    expect(check_2).to receive(:name).twice.and_return(check_2_data[:name])
    expect(Flapjack::Data::Event).to receive(:test_notifications).
      with('events', [check, check_2], an_instance_of(Hash)).twice

    post "/test_notifications/#{check.id},#{check_2.id}", Flapjack.dump_json(:test_notifications => [
      {}, {}
    ]), jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json(:test_notifications => [{
      :summary => summary_both, :links => {:checks => [check.id, check_2.id]}
    }, {
      :summary => summary_both, :links => {:checks => [check.id, check_2.id]}
    }]))
  end

end
