require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::PagerdutyCredentialMethods', :sinatra => true, :logger => true do

  include_context "jsonapi"

  let(:pagerduty_credentials) { double(Flapjack::Data::PagerdutyCredentials, :id => 'abcd') }

  let(:pagerduty_credentials_data) {
    {'service_key' => 'abc',
     'subdomain'   => 'def',
     'username'    => 'ghi',
     'password'    => 'jkl',
    }
  }

  it "creates pagerduty credentials for a contact" # do
  #   expect(Flapjack::Data::Contact).to receive(:find_by_id).
  #     with(contact.id, :redis => redis).and_return(contact)

  #   expect(contact).to receive(:set_pagerduty_credentials).with(pagerduty_credentials)
  #   expect(semaphore).to receive(:release).and_return(true)

  #   post "/contacts/#{contact.id}/pagerduty_credentials",
  #     {:pagerduty_credentials => [pagerduty_credentials]}.to_json, jsonapi_post_env
  #   expect(last_response.status).to eq(201)
  #   expect(last_response.body).to eq('{"pagerduty_credentials":[' +
  #     pagerduty_credentials.merge(:links => {:contacts => [contact.id]}).to_json + ']}')
  # end

  it "does not create pagerduty credentials for a contact that's not present" # do
  #   expect(Flapjack::Data::Contact).to receive(:find_by_id).
  #     with(contact.id, :redis => redis).and_return(nil)
  #   expect(semaphore).to receive(:release).and_return(true)

  #   post "/contacts/#{contact.id}/pagerduty_credentials",
  #     {:pagerduty_credentials => [pagerduty_credentials]}.to_json, jsonapi_post_env
  #   expect(last_response.status).to eq(422)
  # end

  it "returns pagerduty credentials" do
    expect(Flapjack::Data::PagerdutyCredentials).to receive(:find_by_ids!).
      with([pagerduty_credentials.id]).and_return([pagerduty_credentials])

    expect(pagerduty_credentials).to receive(:as_json).
      and_return(pagerduty_credentials_data)
    expect(Flapjack::Data::PagerdutyCredentials).to receive(:associated_ids_for_contact).
      with([pagerduty_credentials.id]).and_return({pagerduty_credentials.id => contact.id})

    get "/pagerduty_credentials/#{pagerduty_credentials.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq({:pagerduty_credentials => [pagerduty_credentials_data]}.to_json)
  end

  it "returns all pagerduty credentials" do
    expect(Flapjack::Data::PagerdutyCredentials).to receive(:all).
      and_return([pagerduty_credentials])

    expect(pagerduty_credentials).to receive(:as_json).
      and_return(pagerduty_credentials_data)
    expect(Flapjack::Data::PagerdutyCredentials).to receive(:associated_ids_for_contact).
      with([pagerduty_credentials.id]).and_return({pagerduty_credentials.id => contact.id})

    get "/pagerduty_credentials"
    expect(last_response).to be_ok
    expect(last_response.body).to eq({:pagerduty_credentials => [pagerduty_credentials_data]}.to_json)
  end

  it "does not return pagerduty credentials if the record is not found"

  it "updates pagerduty credentials" do
    expect(Flapjack::Data::PagerdutyCredentials).to receive(:find_by_ids!).
      with([pagerduty_credentials.id]).and_return([pagerduty_credentials])

    expect(pagerduty_credentials).to receive(:service_key=).with('xyz')
    expect(pagerduty_credentials).to receive(:save).and_return(true)

    patch "/pagerduty_credentials/#{pagerduty_credentials.id}",
      [{:op => 'replace', :path => '/pagerduty_credentials/0/service_key', :value => 'xyz'}].to_json,
      jsonapi_patch_env
    expect(last_response.status).to eq(204)
  end

  it "deletes pagerduty credentials" do
    expect(Flapjack::Data::PagerdutyCredentials).to receive(:find_by_ids!).
      with([pagerduty_credentials.id]).and_return([pagerduty_credentials])

    expect(pagerduty_credentials).to receive(:destroy)

    delete "/pagerduty_credentials/#{pagerduty_credentials.id}"
    expect(last_response.status).to eq(204)
  end

end
