require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::Contacts', :sinatra => true, :logger => true do

  before { skip 'broken, fixing' }

  include_context "jsonapi"

  let(:contact) { double(Flapjack::Data::Contact, :id => '21') }

  let(:contact_data) {
    {:id         => contact.id,
     :name       => "Ada Lovelace",
     :timezone   => 'Australia/Perth',
     # :tags       => ["legend", "first computer programmer"]
    }
  }

  it "creates a contact" do
    expect(Flapjack::Data::Contact).to receive(:lock).with(no_args).and_yield
    expect(Flapjack::Data::Contact).to receive(:exists?).with(contact.id).and_return(false)

    expect(contact).to receive(:invalid?).and_return(false)
    expect(contact).to receive(:save).and_return(true)
    expect(Flapjack::Data::Contact).to receive(:new).
      with(contact_data).and_return(contact)

    post "/contacts", Flapjack.dump_json(:contacts => [contact_data]), jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json([contact.id]))
  end

  it "does not create a contact if the data is improperly formatted" do
    expect(Flapjack::Data::Contact).to receive(:lock).with(no_args).and_yield
    expect(Flapjack::Data::Contact).not_to receive(:exists?)

    errors = double('errors', :full_messages => ['err'])
    expect(contact).to receive(:errors).and_return(errors)

    expect(contact).to receive(:invalid?).and_return(true)
    expect(contact).not_to receive(:save)
    expect(Flapjack::Data::Contact).to receive(:new).and_return(contact)

    post "/contacts", Flapjack.dump_json(:contacts => [{'silly' => 'sausage'}]), jsonapi_post_env
    expect(last_response.status).to eq(403)
  end

  it "returns paginated contacts" do
    expect(Flapjack::Data::Contact).to receive(:count).and_return(1)

    meta = {:pagination => {
      :page        => 1,
      :per_page    => 20,
      :total_pages => 1,
      :total_count => 1
    }}

    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).
      and_return([contact])
    expect(Flapjack::Data::Contact).to receive(:sort).
      with(:name, :order => 'alpha').and_return(sorted)

    contact_ids = double('contact_ids')
    expect(contact_ids).to receive(:associated_ids_for).with(:media).and_return({})
    expect(contact_ids).to receive(:associated_ids_for).with(:pagerduty_credentials).and_return({})
    expect(contact_ids).to receive(:associated_ids_for).with(:rules).and_return({})
    expect(Flapjack::Data::Contact).to receive(:intersect).with(:id => [contact.id]).
      exactly(3).times.and_return(contact_ids)

    expect(contact).to receive(:as_json).and_return(contact_data)

    get '/contacts'
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:contacts => [contact_data], :meta => meta))
  end

  it "returns the core information of a specified contact" do
    contact_ids = double('contact_ids')
    expect(contact_ids).to receive(:associated_ids_for).with(:media).and_return({})
    expect(contact_ids).to receive(:associated_ids_for).with(:pagerduty_credentials).and_return({})
    expect(contact_ids).to receive(:associated_ids_for).with(:rules).and_return({})
    expect(Flapjack::Data::Contact).to receive(:intersect).with(:id => [contact.id]).
      exactly(3).times.and_return(contact_ids)

    expect(contact).to receive(:as_json).and_return(contact_data)
    expect(Flapjack::Data::Contact).to receive(:find_by_ids!).
      with(contact.id).and_return([contact])

    get "/contacts/#{contact.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:contacts => [contact_data]))
  end

  it "does not return information for a contact that does not exist" do
    expect(Flapjack::Data::Contact).to receive(:find_by_ids!).
      with(contact.id).and_raise(Sandstorm::Records::Errors::RecordsNotFound.new(Flapjack::Data::Contact, [contact.id]))

    get "/contacts/#{contact.id}"
    expect(last_response.status).to eq(404)
  end

  it "updates a contact" do
    expect(Flapjack::Data::Contact).to receive(:find_by_ids!).
      with(contact.id).and_return([contact])

    expect(contact).to receive(:name=).with('Elias Ericsson')
    expect(contact).to receive(:save).and_return(true)

    patch "/contacts/#{contact.id}",
      Flapjack.dump_json([{:op => 'replace', :path => '/contacts/0/name', :value => 'Elias Ericsson'}]),
      jsonapi_patch_env
    expect(last_response.status).to eq(204)
  end

  it "deletes a contact" do
    contacts = double('contacts')
    expect(contacts).to receive(:ids).and_return([contact.id])
    expect(contacts).to receive(:destroy_all)
    expect(Flapjack::Data::Contact).to receive(:intersect).
      with(:id => [contact.id]).and_return(contacts)

    delete "/contacts/#{contact.id}"
    expect(last_response.status).to eq(204)
  end

end
