require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::ContactMethods', :sinatra => true, :logger => true do

  include_context "jsonapi"

  let(:contact) { double(Flapjack::Data::Contact, :id => '21') }

  let(:backend) { double(Sandstorm::Backends::Base) }

  let(:contact_data) {
    {:id         => contact.id,
     :first_name => "Ada",
     :last_name  => "Lovelace",
     :email      => "ada@example.com",
     :timezone   => 'Australia/Perth',
     :tags       => ["legend", "first computer programmer"]
    }
  }

  it "creates a contact" do
    expect(Flapjack::Data::Contact).to receive(:backend).and_return(backend)
    expect(backend).to receive(:lock).with(Flapjack::Data::Contact).and_yield

    expect(Flapjack::Data::Contact).to receive(:exists?).with(contact.id).and_return(false)

    expect(contact).to receive(:invalid?).and_return(false)
    expect(contact).to receive(:save).and_return(true)
    expect(Flapjack::Data::Contact).to receive(:new).
      with(contact_data).and_return(contact)

    post "/contacts", {:contacts => [contact_data]}.to_json, jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq([contact.id].to_json)
  end

  it "does not create a contact if the data is improperly formatted" do
    expect(Flapjack::Data::Contact).to receive(:backend).and_return(backend)
    expect(backend).to receive(:lock).with(Flapjack::Data::Contact).and_yield

    expect(Flapjack::Data::Contact).not_to receive(:exists?)

    errors = double('errors', :full_messages => ['err'])
    expect(contact).to receive(:errors).and_return(errors)

    expect(contact).to receive(:invalid?).and_return(true)
    expect(contact).not_to receive(:save)
    expect(Flapjack::Data::Contact).to receive(:new).and_return(contact)

    post "/contacts", {:contacts => [{'silly' => 'sausage'}]}.to_json, jsonapi_post_env
    expect(last_response.status).to eq(403)
  end

  it "returns all the contacts" do
    expect(Flapjack::Data::Contact).to receive(:associated_ids_for_media).
      with([contact.id]).and_return({})
    expect(Flapjack::Data::Contact).to receive(:associated_ids_for_pagerduty_credentials).
      with([contact.id]).and_return({})
    expect(Flapjack::Data::Contact).to receive(:associated_ids_for_notification_rules).
      with([contact.id]).and_return({})
    expect(contact).to receive(:as_json).and_return(contact_data)
    expect(Flapjack::Data::Contact).to receive(:all).and_return([contact])

    get '/contacts'
    expect(last_response).to be_ok
    expect(last_response.body).to eq({:contacts => [contact_data]}.to_json)
  end

  it "returns the core information of a specified contact" do
    expect(Flapjack::Data::Contact).to receive(:associated_ids_for_media).
      with([contact.id]).and_return({})
    expect(Flapjack::Data::Contact).to receive(:associated_ids_for_pagerduty_credentials).
      with([contact.id]).and_return({})
    expect(Flapjack::Data::Contact).to receive(:associated_ids_for_notification_rules).
      with([contact.id]).and_return({})
    expect(contact).to receive(:as_json).and_return(contact_data)
    expect(Flapjack::Data::Contact).to receive(:find_by_ids!).
      with(contact.id).and_return([contact])

    get "/contacts/#{contact.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq({:contacts => [contact_data]}.to_json)
  end

  it "does not return information for a contact that does not exist" do
    expect(Flapjack::Data::Contact).to receive(:find_by_ids!).
      with(contact.id).and_raise(Sandstorm::Records::Errors::RecordsNotFound.new(Flapjack::Data::Contact, [contact.id]))

    get "/contacts/#{contact.id}"
    expect(last_response.status).to eq(404)
  end

  it "updates a contact" do
    expect(Flapjack::Data::Contact).to receive(:find_by_ids).
      with(contact.id).and_return([contact])

    expect(contact).to receive(:first_name=).with('Elias')
    expect(contact).to receive(:save).and_return(true)

    expect(Flapjack::Data::Contact).to receive(:backend).and_return(backend)
    expect(backend).to receive(:lock).with(Flapjack::Data::Contact).and_yield

    patch "/contacts/#{contact.id}",
      [{:op => 'replace', :path => '/contacts/0/first_name', :value => 'Elias'}].to_json,
      jsonapi_patch_env
    expect(last_response.status).to eq(204)
  end

  it "deletes a contact" do
    expect(Flapjack::Data::Contact).to receive(:find_by_ids).
      with(contact.id).and_return([contact])
    expect(contact).to receive(:destroy)

    expect(Flapjack::Data::Contact).to receive(:backend).and_return(backend)
    expect(backend).to receive(:lock).with(Flapjack::Data::Contact).and_yield

    delete "/contacts/#{contact.id}"
    expect(last_response.status).to eq(204)
  end

end
