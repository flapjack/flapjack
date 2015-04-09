require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::PagerdutyCredentialMethods', :sinatra => true, :logger => true do

  include_context "jsonapi"

  let(:contact) { double(Flapjack::Data::Contact, :id => '21') }

  let(:pagerduty_credentials) {
    {'service_key' => 'abc',
     'subdomain'   => 'def',
     'token'       => 'ghi'
    }
  }

  let(:semaphore) {
    double(Flapjack::Data::Semaphore, :resource => 'folly',
           :key => 'semaphores:folly', :expiry => 30, :token => 'spatulas-R-us')
  }

  it "returns pagerduty credentials" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, :redis => redis, :logger => @logger).and_return(contact)

    expect(contact).to receive(:pagerduty_credentials).and_return(pagerduty_credentials)

    aget "/pagerduty_credentials/#{contact.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq({:pagerduty_credentials => [pagerduty_credentials.
        merge(:links => {:contacts => [contact.id]})]}.to_json)
  end

  it "does not return pagerduty credentials if the contact is not present" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, :redis => redis, :logger => @logger).and_return(nil)

    aget "/pagerduty_credentials/#{contact.id}"
    expect(last_response.status).to eq(404)
  end

  it "creates pagerduty credentials for a contact" do
    expect(Flapjack::Data::Semaphore).to receive(:new).
      with("contact_mass_update", :redis => redis, :expiry => 30).and_return(semaphore)

    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(contact)

    expect(contact).to receive(:set_pagerduty_credentials).with(pagerduty_credentials)
    expect(semaphore).to receive(:release).and_return(true)

    apost "/contacts/#{contact.id}/pagerduty_credentials",
      {:pagerduty_credentials => [pagerduty_credentials]}.to_json, jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.headers['Location']).to match(/\/pagerduty_credentials\/#{contact.id}$/)
    expect(last_response.body).to eq([contact.id].to_json)
  end

  it "does not create pagerduty credentials for a contact that's not present" do
    expect(Flapjack::Data::Semaphore).to receive(:new).
      with("contact_mass_update", :redis => redis, :expiry => 30).and_return(semaphore)
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(nil)
    expect(semaphore).to receive(:release).and_return(true)

    apost "/contacts/#{contact.id}/pagerduty_credentials",
      {:pagerduty_credentials => [pagerduty_credentials]}.to_json, jsonapi_post_env
    expect(last_response.status).to eq(422)
  end

  it "updates pagerduty credentials for a contact" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, :logger => @logger, :redis => redis).and_return(contact)

    expect(contact).to receive(:pagerduty_credentials).and_return(pagerduty_credentials)
    expect(contact).to receive(:set_pagerduty_credentials).with(pagerduty_credentials.merge('service_key' => 'xyz'))

    apatch "/pagerduty_credentials/#{contact.id}",
      [{:op => 'replace', :path => '/pagerduty_credentials/0/service_key', :value => 'xyz'}].to_json,
      jsonapi_patch_env
    expect(last_response.status).to eq(204)
  end

  it "does not update pagerduty credentials for a contact that's not present" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, :logger => @logger, :redis => redis).and_return(nil)

    apatch "/pagerduty_credentials/#{contact.id}",
      [{:op => 'replace', :path => '/pagerduty_credentials/0/service_key', :value => 'xyz'}].to_json,
      jsonapi_patch_env
    expect(last_response.status).to eq(404)
  end

  it "deletes the pagerduty credentials for a contact" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, :redis => redis, :logger => @logger).and_return(contact)

    expect(contact).to receive(:delete_pagerduty_credentials)

    adelete "/pagerduty_credentials/#{contact.id}"
    expect(last_response.status).to eq(204)
  end

  it "does not delete the pagerduty credentials of a contact that's not present" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, :redis => redis, :logger => @logger).and_return(nil)

    adelete "/pagerduty_credentials/#{contact.id}"
    expect(last_response.status).to eq(404)
  end

end
