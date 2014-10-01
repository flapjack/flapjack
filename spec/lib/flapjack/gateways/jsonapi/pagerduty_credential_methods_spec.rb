require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::PagerdutyCredentialMethods', :sinatra => true, :logger => true do

  include_context "jsonapi"

  let(:pagerduty_credentials) { double(Flapjack::Data::PagerdutyCredentials, :id => 'abcd') }

  let(:pagerduty_credentials_data) {
    {:service_key => 'abc',
     :subdomain   => 'def',
     :username    => 'ghi',
     :password    => 'jkl',
    }
  }

  let(:contact)      { double(Flapjack::Data::Contact, :id => '21') }

  it "creates pagerduty credentials" do
    expect(Flapjack::Data::Contact).to receive(:lock).
      with(Flapjack::Data::PagerdutyCredentials).and_yield

    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id).and_return(contact)

    expect(pagerduty_credentials).to receive(:invalid?).and_return(false)
    expect(pagerduty_credentials).to receive(:save).and_return(true)
    expect(Flapjack::Data::PagerdutyCredentials).to receive(:new).
      with(pagerduty_credentials_data.merge(:id => nil)).
      and_return(pagerduty_credentials)

    expect(contact).to receive(:pagerduty_credentials).and_return(nil)
    expect(contact).to receive(:pagerduty_credentials=).with(pagerduty_credentials)

    post "/contacts/#{contact.id}/pagerduty_credentials",
      Flapjack.dump_json(:pagerduty_credentials => [pagerduty_credentials_data]),
      jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json([pagerduty_credentials.id]))
  end

  it "does not create pagerduty credentials if the data is improperly formatted" do
    expect(Flapjack::Data::Contact).to receive(:lock).
      with(Flapjack::Data::PagerdutyCredentials).and_yield

    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id).and_return(contact)

    errors = double('errors', :full_messages => ['err'])
    expect(pagerduty_credentials).to receive(:errors).and_return(errors)

    expect(pagerduty_credentials).to receive(:invalid?).and_return(true)
    expect(pagerduty_credentials).not_to receive(:save)
    expect(Flapjack::Data::PagerdutyCredentials).to receive(:new).and_return(pagerduty_credentials)

    post "/contacts/#{contact.id}/pagerduty_credentials",
      Flapjack.dump_json(:pagerduty_credentials => [{'silly' => 'sausage'}]),
      jsonapi_post_env
    expect(last_response.status).to eq(403)
  end

  it "does not create pagerduty credentials if the contact doesn't exist" do
    expect(Flapjack::Data::Contact).to receive(:lock).
      with(Flapjack::Data::PagerdutyCredentials).and_yield

    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id).and_return(nil)

    post "/contacts/#{contact.id}/pagerduty_credentials",
      Flapjack.dump_json(:pagerduty_credentials => [pagerduty_credentials_data]),
      jsonapi_post_env
    expect(last_response.status).to eq(403)
  end

  it "returns pagerduty credentials" do
    expect(Flapjack::Data::PagerdutyCredentials).to receive(:find_by_ids!).
      with(pagerduty_credentials.id).and_return([pagerduty_credentials])

    expect(pagerduty_credentials).to receive(:as_json).
      and_return(pagerduty_credentials_data)
    expect(Flapjack::Data::PagerdutyCredentials).to receive(:associated_ids_for_contact).
      with(pagerduty_credentials.id).and_return({pagerduty_credentials.id => contact.id})

    get "/pagerduty_credentials/#{pagerduty_credentials.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:pagerduty_credentials => [pagerduty_credentials_data]))
  end

  it "returns all pagerduty credentials" do
    expect(Flapjack::Data::PagerdutyCredentials).to receive(:all).
      and_return([pagerduty_credentials])

    expect(pagerduty_credentials).to receive(:as_json).
      and_return(pagerduty_credentials_data)
    expect(Flapjack::Data::PagerdutyCredentials).to receive(:associated_ids_for_contact).
      with(pagerduty_credentials.id).and_return({pagerduty_credentials.id => contact.id})

    get "/pagerduty_credentials"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:pagerduty_credentials => [pagerduty_credentials_data]))
  end

  it "does not return pagerduty credentials if the record is not found"

  it "updates pagerduty credentials" do
    expect(Flapjack::Data::PagerdutyCredentials).to receive(:find_by_ids!).
      with(pagerduty_credentials.id).and_return([pagerduty_credentials])

    expect(pagerduty_credentials).to receive(:service_key=).with('xyz')
    expect(pagerduty_credentials).to receive(:save).and_return(true)

    patch "/pagerduty_credentials/#{pagerduty_credentials.id}",
      Flapjack.dump_json([{:op => 'replace', :path => '/pagerduty_credentials/0/service_key', :value => 'xyz'}]),
      jsonapi_patch_env
    expect(last_response.status).to eq(204)
  end

  it "deletes pagerduty credentials" do
    expect(Flapjack::Data::PagerdutyCredentials).to receive(:find_by_ids!).
      with(pagerduty_credentials.id).and_return([pagerduty_credentials])

    expect(pagerduty_credentials).to receive(:destroy)

    delete "/pagerduty_credentials/#{pagerduty_credentials.id}"
    expect(last_response.status).to eq(204)
  end

end
