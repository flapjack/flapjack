require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::Contacts', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:contact)   { double(Flapjack::Data::Contact, :id => contact_data[:id]) }
  let(:contact_2) { double(Flapjack::Data::Contact, :id => contact_2_data[:id]) }

  let(:medium)    { double(Flapjack::Data::Medium, :id => email_data[:id]) }

  def contact_json(co_data)
    id = co_data[:id]
    {
      :id => id,
      :type => 'contact',
      :attributes => co_data.reject {|k,v| :id.eql?(k) },
      :relationships => {
        :checks => {
          :links => {
            :self => "http://example.org/contacts/#{id}/relationships/checks",
            :related => "http://example.org/contacts/#{id}/checks"
          }
        },
        :media => {
          :links => {
            :self => "http://example.org/contacts/#{id}/relationships/media",
            :related => "http://example.org/contacts/#{id}/media"
          }
        },
        :rules => {
          :links => {
            :self => "http://example.org/contacts/#{id}/relationships/rules",
            :related => "http://example.org/contacts/#{id}/rules"
          }
        }
      }
    }
  end

  it "creates a contact" do
    expect(Flapjack::Data::Contact).to receive(:lock).
      with(Flapjack::Data::Medium, Flapjack::Data::Rule, Flapjack::Data::Check,
           Flapjack::Data::ScheduledMaintenance).and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Contact).to receive(:intersect).
      with(:id => [contact_data[:id]]).and_return(empty_ids)

    expect(contact).to receive(:invalid?).and_return(false)
    expect(contact).to receive(:save!).and_return(true)
    expect(Flapjack::Data::Contact).to receive(:new).with(contact_data).
      and_return(contact)

    expect(contact).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(contact_data)

    expect(Flapjack::Data::Contact).to receive(:jsonapi_type).and_return('contact')

    post "/contacts", Flapjack.dump_json(:data => contact_data.merge(:type => 'contact')), jsonapi_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data =>
      contact_json(contact_data)))
  end

  it "does not create a contact if the data is improperly formatted" do
    expect(Flapjack::Data::Contact).to receive(:lock).
      with(Flapjack::Data::Medium, Flapjack::Data::Rule, Flapjack::Data::Check,
           Flapjack::Data::ScheduledMaintenance).and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Contact).to receive(:intersect).
      with(:id => [contact_data[:id]]).and_return(empty_ids)

    errors = double('errors', :full_messages => ['err'])
    expect(contact).to receive(:errors).and_return(errors)

    expect(contact).to receive(:invalid?).and_return(true)
    expect(contact).not_to receive(:save!)
    expect(Flapjack::Data::Contact).to receive(:new).with(contact_data).
      and_return(contact)

    post "/contacts", Flapjack.dump_json(:data => contact_data.merge(:type => 'contact')), jsonapi_env
    expect(last_response.status).to eq(403)
  end

  it "returns paginated contacts" do
    expect(Flapjack::Data::Contact).to receive(:lock).
      with(Flapjack::Data::Check, Flapjack::Data::Medium, Flapjack::Data::Rule,
           Flapjack::Data::ScheduledMaintenance).and_yield

    meta = {:pagination => {
      :page        => 1,
      :per_page    => 20,
      :total_pages => 1,
      :total_count => 1
    }}

    links = {
      :self  => 'http://example.org/contacts',
      :first => 'http://example.org/contacts?page=1',
      :last  => 'http://example.org/contacts?page=1'
    }

    page = double('page')
    expect(page).to receive(:empty?).and_return(false)
    expect(page).to receive(:ids).and_return([contact.id])
    expect(page).to receive(:collect) {|&arg| [arg.call(contact)] }
    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).
      and_return(page)
    expect(sorted).to receive(:count).and_return(1)
    expect(Flapjack::Data::Contact).to receive(:sort).with(:id).
      and_return(sorted)

    expect(contact).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(contact_data)

    expect(Flapjack::Data::Contact).to receive(:jsonapi_type).and_return('contact')

    get '/contacts'
    expect(last_response).to be_ok
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data => [
      contact_json(contact_data)], :links => links, :meta => meta))
  end

  it "retrieves paginated contacts matching a filter" do
    expect(Flapjack::Data::Contact).to receive(:lock).
      with(Flapjack::Data::Check, Flapjack::Data::Medium, Flapjack::Data::Rule,
           Flapjack::Data::ScheduledMaintenance).and_yield

    meta = {
      :pagination => {
        :page        => 1,
        :per_page    => 20,
        :total_pages => 1,
        :total_count => 1
      }
    }

    links = {
      :self  => 'http://example.org/contacts?filter%5B%5D=name%3AJim+Smith',
      :first => 'http://example.org/contacts?filter%5B%5D=name%3AJim+Smith&page=1',
      :last  => 'http://example.org/contacts?filter%5B%5D=name%3AJim+Smith&page=1'
    }

    filtered = double('filtered')
    expect(Flapjack::Data::Contact).to receive(:intersect).with(:name => 'Jim Smith').
      and_return(filtered)

    page = double('page')
    expect(page).to receive(:empty?).and_return(false)
    expect(page).to receive(:ids).and_return([contact.id])
    expect(page).to receive(:collect) {|&arg| [arg.call(contact)] }
    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).and_return(page)
    expect(sorted).to receive(:count).and_return(1)
    expect(filtered).to receive(:sort).with(:id).and_return(sorted)

    expect(contact).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(contact_data)

    expect(Flapjack::Data::Contact).to receive(:jsonapi_type).and_return('contact')

    get '/contacts?filter=name%3AJim+Smith'
    expect(last_response).to be_ok
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data =>
      [contact_json(contact_data)], :links => links, :meta => meta))
  end

  it "retrieves paginated contacts matching two filter values" do
    expect(Flapjack::Data::Contact).to receive(:lock).
      with(Flapjack::Data::Check, Flapjack::Data::Medium, Flapjack::Data::Rule,
           Flapjack::Data::ScheduledMaintenance).and_yield

    meta = {
      :pagination => {
        :page        => 1,
        :per_page    => 20,
        :total_pages => 1,
        :total_count => 1
      }
    }

    links = {
      :self  => 'http://example.org/contacts?filter%5B%5D=name%3AJim+Smith&filter%5B%5D=timezone%3A%2FUTC%2F',
      :first => 'http://example.org/contacts?filter%5B%5D=name%3AJim+Smith&filter%5B%5D=timezone%3A%2FUTC%2F&page=1',
      :last  => 'http://example.org/contacts?filter%5B%5D=name%3AJim+Smith&filter%5B%5D=timezone%3A%2FUTC%2F&page=1'
    }

    filtered = double('filtered')
    expect(Flapjack::Data::Contact).to receive(:intersect).with(:name => 'Jim Smith', :timezone => Regexp.new(/UTC/)).
      and_return(filtered)

    page = double('page')
    expect(page).to receive(:empty?).and_return(false)
    expect(page).to receive(:ids).and_return([contact.id])
    expect(page).to receive(:collect) {|&arg| [arg.call(contact)] }
    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).and_return(page)
    expect(sorted).to receive(:count).and_return(1)
    expect(filtered).to receive(:sort).with(:id).and_return(sorted)

    expect(contact).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(contact_data)

    expect(Flapjack::Data::Contact).to receive(:jsonapi_type).and_return('contact')

    get '/contacts?filter%5B%5D=name%3AJim+Smith&filter%5B%5D=timezone%3A%2FUTC%2F'
    expect(last_response).to be_ok
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data =>
      [contact_json(contact_data)], :links => links, :meta => meta))
  end

  it "returns the second page of a multi-page contact list" do
    expect(Flapjack::Data::Contact).to receive(:lock).
      with(Flapjack::Data::Check, Flapjack::Data::Medium, Flapjack::Data::Rule,
           Flapjack::Data::ScheduledMaintenance).and_yield

    meta = {:pagination => {
      :page        => 2,
      :per_page    => 3,
      :total_pages => 3,
      :total_count => 8
    }}

    links = {
      :self  => 'http://example.org/contacts?page=2&per_page=3',
      :first => 'http://example.org/contacts?page=1&per_page=3',
      :last  => 'http://example.org/contacts?page=3&per_page=3',
      :next  => 'http://example.org/contacts?page=3&per_page=3',
      :prev  => 'http://example.org/contacts?page=1&per_page=3'
    }

    contact_3_data = {:id => SecureRandom.uuid, :name => 'Bill Brown'}
    contact_3 = double(Flapjack::Data::Contact, :id => contact_3_data[:id])

    page = double('page')
    expect(page).to receive(:empty?).and_return(false)
    expect(page).to receive(:ids).and_return([contact.id])
    expect(page).to receive(:collect) {|&arg| [
      arg.call(contact), arg.call(contact_2), arg.call(contact_3)
    ] }
    sorted = double('sorted')
    expect(sorted).to receive(:page).with(2, :per_page => 3).
      and_return(page)
    expect(sorted).to receive(:count).and_return(8)
    expect(Flapjack::Data::Contact).to receive(:sort).with(:id).
      and_return(sorted)

    expect(contact).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(contact_data)
    expect(contact_2).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(contact_2_data)
    expect(contact_3).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(contact_3_data)

    expect(Flapjack::Data::Contact).to receive(:jsonapi_type).and_return('contact')

    get '/contacts?page=2&per_page=3'
    expect(last_response).to be_ok
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data => [
      contact_json(contact_data), contact_json(contact_2_data),
      contact_json(contact_3_data)], :links => links, :meta => meta))
  end

  it "returns paginated sorted contacts" do
    expect(Flapjack::Data::Contact).to receive(:lock).
      with(Flapjack::Data::Check, Flapjack::Data::Medium, Flapjack::Data::Rule,
           Flapjack::Data::ScheduledMaintenance).and_yield

    meta = {:pagination => {
      :page        => 1,
      :per_page    => 20,
      :total_pages => 1,
      :total_count => 2
    }}

    links = {
      :self  => 'http://example.org/contacts?sort=-name',
      :first => 'http://example.org/contacts?page=1&sort=-name',
      :last  => 'http://example.org/contacts?page=1&sort=-name'
    }

    page = double('page')
    expect(page).to receive(:empty?).and_return(false)
    expect(page).to receive(:ids).and_return([contact.id])
    expect(page).to receive(:collect) {|&arg| [
      arg.call(contact_2), arg.call(contact)
    ] }
    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).
      and_return(page)
    expect(sorted).to receive(:count).and_return(2)
    expect(Flapjack::Data::Contact).to receive(:sort).with(:name => :desc).
      and_return(sorted)

    expect(contact_2).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(contact_2_data)
    expect(contact).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(contact_data)

    expect(Flapjack::Data::Contact).to receive(:jsonapi_type).and_return('contact')

    get '/contacts?sort=-name'
    expect(last_response).to be_ok

    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data => [
      contact_json(contact_2_data), contact_json(contact_data)],
      :links => links, :meta => meta))
  end

  it "does not return contacts if sort parameter is incorrectly specified" do
    expect(Flapjack::Data::Contact).to receive(:lock).
      with(Flapjack::Data::Check, Flapjack::Data::Medium, Flapjack::Data::Rule,
           Flapjack::Data::ScheduledMaintenance).and_yield
    expect(Flapjack::Data::Contact).not_to receive(:sort)

    get '/contacts?sort=enabled'
    expect(last_response.status).to eq(403)
    # TODO error structure
  end

  it "returns a contact" do
    expect(Flapjack::Data::Contact).to receive(:lock).
      with(Flapjack::Data::Check, Flapjack::Data::Medium, Flapjack::Data::Rule,
           Flapjack::Data::ScheduledMaintenance).and_yield

    expect(Flapjack::Data::Contact).to receive(:intersect).
      with(:id => contact.id).and_return([contact])

    expect(contact).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(contact_data)

    expect(Flapjack::Data::Contact).to receive(:jsonapi_type).and_return('contact')

    get "/contacts/#{contact.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data =>
      contact_json(contact_data), :links => {
      :self  => "http://example.org/contacts/#{contact.id}",
    }))
  end

  it "does not return a contact that does not exist" do
    expect(Flapjack::Data::Contact).to receive(:lock).
      with(Flapjack::Data::Check, Flapjack::Data::Medium, Flapjack::Data::Rule,
           Flapjack::Data::ScheduledMaintenance).and_yield

    no_contacts = double('no_contacts')
    expect(no_contacts).to receive(:empty?).and_return(true)

    expect(Flapjack::Data::Contact).to receive(:intersect).
      with(:id => contact.id).and_return(no_contacts)

    get "/contacts/#{contact.id}"
    expect(last_response.status).to eq(404)
  end

  it 'returns a contact and the transport and address of its media records' do
    expect(Flapjack::Data::Contact).to receive(:lock).
      with(Flapjack::Data::Check, Flapjack::Data::Medium, Flapjack::Data::Rule,
           Flapjack::Data::ScheduledMaintenance).and_yield

    contacts = double('contacts')
    expect(contacts).to receive(:empty?).and_return(false)
    expect(contacts).to receive(:collect) {|&arg| [arg.call(contact)] }
    expect(contacts).to receive(:associated_ids_for).with(:media).
      and_return(contact.id => [medium.id])

    full_media = double('full_media')
    expect(full_media).to receive(:collect) {|&arg| [arg.call(medium)] }

    expect(Flapjack::Data::Medium).to receive(:intersect).
      with(:id => [medium.id]).and_return(full_media)

    expect(medium).to receive(:as_json).with(:only => [:transport, :address]).
      and_return(:transport => email_data[:transport], :address => email_data[:address])

    expect(Flapjack::Data::Contact).to receive(:intersect).
      with(:id => contact.id).and_return(contacts)

    expect(contact).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(contact_data)

    expect(Flapjack::Data::Contact).to receive(:jsonapi_type).and_return('contact')
    expect(Flapjack::Data::Medium).to receive(:jsonapi_type).twice.and_return('medium')

    get "/contacts/#{contact.id}?fields[media]=transport,address&include=media"
    expect(last_response).to be_ok

    response_data = contact_json(contact_data)
    response_data[:relationships][:media][:data] = [{:type => 'medium', :id => medium.id}]

    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data => response_data,
      :included => [{
        :type => 'medium',
        :id => medium.id,
        :attributes => {
          :transport => email_data[:transport],
          :address => email_data[:address]
        },
        :relationships => {
          :alerting_checks => {
            :links => {
              :self => "http://example.org/media/#{medium.id}/relationships/alerting_checks",
              :related => "http://example.org/media/#{medium.id}/alerting_checks"
            }
          },
          :contact => {
            :links => {
              :self => "http://example.org/media/#{medium.id}/relationships/contact",
              :related => "http://example.org/media/#{medium.id}/contact"
            }
          },
          :rules => {
            :links => {
              :self => "http://example.org/media/#{medium.id}/relationships/rules",
              :related => "http://example.org/media/#{medium.id}/rules"
            }
          }
        }
      }],
      :links => {
        :self  => "http://example.org/contacts/#{contact.id}?fields%5Bmedia%5D=transport%2Caddress&include=media",
      }))
  end

  it "updates a contact" do
    expect(Flapjack::Data::Contact).to receive(:lock).
      with(Flapjack::Data::Medium, Flapjack::Data::Rule, Flapjack::Data::Check,
           Flapjack::Data::ScheduledMaintenance).and_yield

    expect(Flapjack::Data::Contact).to receive(:find_by_id!).
      with(contact.id).and_return(contact)

    expect(contact).to receive(:name=).with('Elias Ericsson')
    expect(contact).to receive(:invalid?).and_return(false)
    expect(contact).to receive(:save!).and_return(true)

    patch "/contacts/#{contact.id}",
      Flapjack.dump_json(:data => {:id => contact.id,
        :type => 'contact', :name => 'Elias Ericsson'}),
      jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it "deletes a contact" do
    expect(Flapjack::Data::Contact).to receive(:lock).
      with(Flapjack::Data::Medium, Flapjack::Data::Rule, Flapjack::Data::Check,
           Flapjack::Data::ScheduledMaintenance).and_yield

    contacts = double('contacts')
    expect(contact).to receive(:destroy)
    expect(Flapjack::Data::Contact).to receive(:find_by_id!).
      with(contact.id).and_return(contact)

    delete "/contacts/#{contact.id}"
    expect(last_response.status).to eq(204)
  end

end
