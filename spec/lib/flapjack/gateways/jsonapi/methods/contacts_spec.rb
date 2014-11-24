require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::Contacts', :sinatra => true, :logger => true, :pact_fixture => true do

  # before { skip 'broken, fixing' }

  include_context "jsonapi"

  let(:contact) { double(Flapjack::Data::Contact, :id => contact_data[:id]) }

  it "creates a contact" do
    expect(Flapjack::Data::Contact).to receive(:lock).with(no_args).and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Contact).to receive(:intersect).
      with(:id => [contact_data[:id]]).and_return(empty_ids)

    expect(contact).to receive(:invalid?).and_return(false)
    expect(contact).to receive(:save).and_return(true)
    expect(Flapjack::Data::Contact).to receive(:new).with(contact_data).
      and_return(contact)

    expect(Flapjack::Data::Contact).to receive(:as_jsonapi).
      with(:resources => [contact], :ids => [contact.id], :unwrap => true).
      and_return(contact_data)

    post "/contacts", Flapjack.dump_json(:contacts => contact_data), jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json(:contacts => contact_data))
  end

  it "does not create a contact if the data is improperly formatted" do
    expect(Flapjack::Data::Contact).to receive(:lock).with(no_args).and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Contact).to receive(:intersect).
      with(:id => [contact_data[:id]]).and_return(empty_ids)

    errors = double('errors', :full_messages => ['err'])
    expect(contact).to receive(:errors).and_return(errors)

    expect(contact).to receive(:invalid?).and_return(true)
    expect(contact).not_to receive(:save)
    expect(Flapjack::Data::Contact).to receive(:new).with(contact_data).
      and_return(contact)

    expect(Flapjack::Data::Contact).not_to receive(:as_jsonapi)

    post "/contacts", Flapjack.dump_json(:contacts => contact_data), jsonapi_post_env
    expect(last_response.status).to eq(403)
  end

  it "returns paginated contacts" do
    meta = {:pagination => {
      :page        => 1,
      :per_page    => 20,
      :total_pages => 1,
      :total_count => 1
    }}

    expect(Flapjack::Data::Contact).to receive(:count).and_return(1)

    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).
      and_return([contact])
    expect(Flapjack::Data::Contact).to receive(:sort).with(:name).
      and_return(sorted)

    expect(Flapjack::Data::Contact).to receive(:as_jsonapi).
      with(:resources => [contact], :ids => [contact.id],
           :fields => an_instance_of(Array), :unwrap => false).
      and_return([contact_data])

    get '/contacts'
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:contacts => [contact_data], :meta => meta))
  end

  it "returns a contact" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id!).
      with(contact.id).and_return(contact)
    expect(Flapjack::Data::Contact).to receive(:as_jsonapi).
      with(:resources => [contact], :ids => [contact.id],
           :fields => an_instance_of(Array), :unwrap => true).
      and_return(contact_data)

    get "/contacts/#{contact.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:contacts => contact_data))
  end

  it "does not return a contact that does not exist" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id!).
      with(contact.id).and_raise(Sandstorm::Records::Errors::RecordNotFound.new(Flapjack::Data::Contact, contact.id))

    get "/contacts/#{contact.id}"
    expect(last_response.status).to eq(404)
  end

  it "updates a contact" do
    expect(Flapjack::Data::Contact).to receive(:find_by_ids!).
      with(contact.id).and_return([contact])

    expect(contact).to receive(:name=).with('Elias Ericsson')
    expect(contact).to receive(:invalid?).and_return(false)
    expect(contact).to receive(:save).and_return(true)

    put "/contacts/#{contact.id}",
      Flapjack.dump_json(:contacts => {:id => contact.id, :name => 'Elias Ericsson'}),
      jsonapi_put_env
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
