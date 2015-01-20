require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::ContactMethods', :sinatra => true, :logger => true do

  include_context "jsonapi"

  let(:contact)      { double(Flapjack::Data::Contact, :id => '21') }
  let(:contact_core) {
    {'id'         => contact.id,
     'first_name' => "Ada",
     'last_name'  => "Lovelace",
     'email'      => "ada@example.com",
     'tags'       => ["legend", "first computer programmer"]
    }
  }

  let(:semaphore) {
    double(Flapjack::Data::Semaphore, :resource => 'folly',
           :key => 'semaphores:folly', :expiry => 30, :token => 'spatulas-R-us')
  }

  it "returns all the contacts" do
    expect(Flapjack::Data::Contact).to receive(:entity_ids_for).
      with([contact.id], :redis => redis).and_return({})
    expect(contact).to receive(:to_jsonapi).and_return(contact_core.to_json)
    expect(Flapjack::Data::Contact).to receive(:all).with(:redis => redis).
      and_return([contact])

    aget '/contacts'
    expect(last_response).to be_ok
    expect(last_response.body).to eq({:contacts => [contact_core]}.to_json)
  end

  it "skips contacts without ids when getting all" do
    idless_contact = double(Flapjack::Data::Contact, :id => '')

    expect(Flapjack::Data::Contact).to receive(:entity_ids_for).
      with([contact.id], :redis => redis).and_return({})
    expect(contact).to receive(:to_jsonapi).and_return(contact_core.to_json)
    expect(idless_contact).not_to receive(:to_jsonapi)
    expect(Flapjack::Data::Contact).to receive(:all).with(:redis => redis).
      and_return([contact, idless_contact])

    aget '/contacts'
    expect(last_response).to be_ok
    expect(last_response.body).to eq({:contacts => [contact_core]}.to_json)
  end

  it "returns the core information of a specified contact" do
    expect(Flapjack::Data::Contact).to receive(:entity_ids_for).
      with([contact.id], :redis => redis).and_return({})
    expect(contact).to receive(:to_jsonapi).and_return(contact_core.to_json)
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(contact)

    aget "/contacts/#{contact.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq({:contacts => [contact_core]}.to_json)
  end

  it "does not return information for a contact that does not exist" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(nil)

    aget "/contacts/#{contact.id}"
    expect(last_response.status).to eq(404)
  end

  it "creates a contact with supplied ID" do
    #FIXME: I think media should be removed from this interface
    contact_data = {
      "id"         => "0362",
      "first_name" => "John",
      "last_name"  => "Smith",
      "email"      => "johns@example.dom",
      "media"      => {
        "email"  => "johns@example.dom",
        "jabber" => "johns@conference.localhost"
      }
    }

    expect(Flapjack::Data::Semaphore).to receive(:new).
      with("contact_mass_update", {:redis => redis, :expiry => 30}).and_return(semaphore)
    expect(Flapjack::Data::Contact).to receive(:exists_with_id?).
      with("0362", {:redis => redis}).and_return(false)
    expect(Flapjack::Data::Contact).to receive(:add).
      with(contact_data, {:redis => redis}).and_return(contact)
    expect(semaphore).to receive(:release).and_return(true)

    apost "/contacts", {:contacts => [contact_data]}.to_json, jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(["0362"].to_json)
  end

  it "updates a contact" do
    expect(Flapjack::Data::Semaphore).to receive(:new).
      with("contact_mass_update", {:redis => redis, :expiry => 30}).and_return(semaphore)
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('1234', :logger => @logger, :redis => redis).and_return(contact)

    expect(contact).to receive(:update).with('first_name' => 'Elias').and_return(nil)
    expect(contact).to receive(:update).with('timezone' => 'Asia/Shanghai').and_return(nil)
    expect(semaphore).to receive(:release).and_return(true)

    apatch "/contacts/1234",
      [{:op => 'replace', :path => '/contacts/0/first_name', :value => 'Elias'},
       {:op => 'replace', :path => '/contacts/0/timezone', :value => 'Asia/Shanghai'}].to_json,
      jsonapi_patch_env
    expect(last_response.status).to eq(204)
  end

  it "deletes a contact" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(contact)
    expect(Flapjack::Data::Semaphore).to receive(:new).and_return(semaphore)
    expect(semaphore).to receive(:release)
    expect(contact).to receive(:delete!)

    adelete "/contacts/21"
    expect(last_response.status).to eq(204)
  end

  it "does not create a contact if the data is improperly formatted" do
    expect(Flapjack::Data::Contact).not_to receive(:add)

    apost "/contacts", {'sausage' => 'good'}.to_json, jsonapi_post_env
    expect(last_response.status).to eq(422)
  end

end
