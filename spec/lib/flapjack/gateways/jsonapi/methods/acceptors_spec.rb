require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::Acceptors', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:acceptor)    { double(Flapjack::Data::Acceptor, :id => acceptor_data[:id]) }
  let(:acceptor_2)  { double(Flapjack::Data::Acceptor, :id => acceptor_2_data[:id]) }

  let(:contact) { double(Flapjack::Data::Contact, :id => contact_data[:id]) }

  let(:medium)  { double(Flapjack::Data::Medium, :id => email_data[:id]) }

  # TODO reject if not linked to contact on creation
  it "creates an acceptor" do
    expect(Flapjack::Data::Acceptor).to receive(:lock).
      with(no_args).
      and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Acceptor).to receive(:intersect).
      with(:id => [acceptor_data[:id]]).and_return(empty_ids)

    expect(acceptor).to receive(:invalid?).and_return(false)
    expect(acceptor).to receive(:save!).and_return(true)
    expect(Flapjack::Data::Acceptor).to receive(:new).with(acceptor_data).
      and_return(acceptor)

    expect(acceptor).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(acceptor_data.reject {|k,v| :id.eql?(k)})

    req_data  = acceptor_json(acceptor_data)
    resp_data = req_data.merge(:relationships => acceptor_rel(acceptor_data))

    post "/acceptors", Flapjack.dump_json(:data => req_data), jsonapi_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data =>
      resp_data))
  end

  it "creates an acceptor, linked to a contact" do
    expect(Flapjack::Data::Acceptor).to receive(:lock).
      with(Flapjack::Data::Contact).
      and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Acceptor).to receive(:intersect).
      with(:id => [acceptor_data[:id]]).and_return(empty_ids)

    expect(acceptor).to receive(:invalid?).and_return(false)
    expect(acceptor).to receive(:save!).and_return(true)
    expect(Flapjack::Data::Acceptor).to receive(:new).with(acceptor_data).
      and_return(acceptor)

    expect(Flapjack::Data::Contact).to receive(:find_by_id!).
      with(contact.id).and_return(contact)
    expect(acceptor).to receive(:'contact=').with(contact)

    req_data  = acceptor_json(acceptor_data).merge(
      :relationships => {
        :contact => {
          :data => {:type => 'contact', :id => contact_data[:id]}
        }
      }
    )
    resp_data = req_data.merge(:relationships => acceptor_rel(acceptor_data))

    expect(acceptor).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(acceptor_data.reject {|k,v| :id.eql?(k)})

    post "/acceptors", Flapjack.dump_json(:data => req_data), jsonapi_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data =>
      resp_data))
  end

  it "does not create an acceptor if the data is improperly formatted" do
    expect(Flapjack::Data::Acceptor).to receive(:lock).
      with(no_args).
      and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Acceptor).to receive(:intersect).
      with(:id => [acceptor_data[:id]]).and_return(empty_ids)

    errors = double('errors', :full_messages => ['err'])
    expect(acceptor).to receive(:errors).and_return(errors)

    expect(acceptor).to receive(:invalid?).and_return(true)
    expect(acceptor).not_to receive(:save!)
    expect(Flapjack::Data::Acceptor).to receive(:new).with(acceptor_data).
      and_return(acceptor)

    req_data  = acceptor_json(acceptor_data)

    post "/acceptors", Flapjack.dump_json(:data => req_data), jsonapi_env
    expect(last_response.status).to eq(403)
  end

  it "gets all acceptors" do
    expect(Flapjack::Data::Acceptor).to receive(:lock).
      with(no_args).
      and_yield

    meta = {
      :pagination => {
        :page        => 1,
        :per_page    => 20,
        :total_pages => 1,
        :total_count => 1
      }
    }

    links = {
      :self  => 'http://example.org/acceptors',
      :first => 'http://example.org/acceptors?page=1',
      :last  => 'http://example.org/acceptors?page=1'
    }

    page = double('page')
    expect(page).to receive(:empty?).and_return(false)
    expect(page).to receive(:ids).and_return([acceptor.id])
    expect(page).to receive(:collect) {|&arg| [arg.call(acceptor)] }
    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).
      and_return(page)
    expect(sorted).to receive(:count).and_return(1)
    expect(Flapjack::Data::Acceptor).to receive(:sort).
      with(:id).and_return(sorted)

    expect(acceptor).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(acceptor_data.reject {|k,v| :id.eql?(k)})

    resp_data = [acceptor_json(acceptor_data).merge(:relationships => acceptor_rel(acceptor_data))]

    get '/acceptors'
    expect(last_response).to be_ok
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data => resp_data,
      :links => links, :meta => meta))
  end

  it "gets a single acceptor" do
    expect(Flapjack::Data::Acceptor).to receive(:lock).
      with(no_args).
      and_yield

    expect(Flapjack::Data::Acceptor).to receive(:intersect).
      with(:id => acceptor.id).and_return([acceptor])

    expect(acceptor).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(acceptor_data.reject {|k,v| :id.eql?(k)})

    resp_data = acceptor_json(acceptor_data).merge(:relationships => acceptor_rel(acceptor_data))

    get "/acceptors/#{acceptor.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data =>
      resp_data, :links => {:self  => "http://example.org/acceptors/#{acceptor.id}"}))
  end

  it "does not get an acceptor that does not exist" do
    expect(Flapjack::Data::Acceptor).to receive(:lock).
      with(no_args).
      and_yield

    no_acceptors = double('no_acceptors')
    expect(no_acceptors).to receive(:empty?).and_return(true)

    expect(Flapjack::Data::Acceptor).to receive(:intersect).
      with(:id => acceptor.id).and_return(no_acceptors)

    get "/acceptors/#{acceptor.id}"
    expect(last_response).to be_not_found
  end

  it "retrieves an acceptor and its linked contact record" do
    expect(Flapjack::Data::Acceptor).to receive(:lock).
      with(Flapjack::Data::Contact).
      and_yield

    acceptors = double('acceptors')
    expect(acceptors).to receive(:empty?).and_return(false)
    expect(acceptors).to receive(:collect) {|&arg| [arg.call(acceptor)] }
    expect(acceptors).to receive(:associated_ids_for).with(:contact).
      and_return(acceptor.id => contact.id)
    expect(Flapjack::Data::Acceptor).to receive(:intersect).
      with(:id => acceptor.id).and_return(acceptors)

    contacts = double('contacts')
    expect(contacts).to receive(:collect) {|&arg| [arg.call(contact)] }
    expect(Flapjack::Data::Contact).to receive(:intersect).
      with(:id => [contact.id]).and_return(contacts)

    expect(contact).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(contact_data.reject {|k,v| :id.eql?(k)})

    expect(acceptor).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(acceptor_data.reject {|k,v| :id.eql?(k)})

    get "/acceptors/#{acceptor.id}?include=contact"
    expect(last_response).to be_ok

    resp_data = acceptor_json(acceptor_data).merge(:relationships => acceptor_rel(acceptor_data))
    resp_data[:relationships][:contact][:data] = {:type => 'contact', :id => contact.id}

    resp_included = [contact_json(contact_data).merge(:relationships => contact_rel(contact_data))]

    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data => resp_data,
      :included => resp_included,
      :links => {:self  => "http://example.org/acceptors/#{acceptor.id}?include=contact"}))
  end

  it "retrieves an acceptor, its contact, and all of its contact's media records" do
    expect(Flapjack::Data::Acceptor).to receive(:lock).
      with(Flapjack::Data::Contact,
           Flapjack::Data::Medium).
      and_yield

    acceptors = double('acceptors')
    expect(acceptors).to receive(:empty?).and_return(false)
    expect(acceptors).to receive(:collect) {|&arg| [arg.call(acceptor)] }
    expect(acceptors).to receive(:associated_ids_for).with(:contact).
      and_return(acceptor.id => contact.id)
    expect(Flapjack::Data::Acceptor).to receive(:intersect).
      with(:id => acceptor.id).and_return(acceptors)

    contacts = double('contacts')
    expect(contacts).to receive(:collect) {|&arg| [arg.call(contact)] }
    expect(contacts).to receive(:associated_ids_for).with(:media).
      and_return({contact.id => [medium.id]})
    expect(Flapjack::Data::Contact).to receive(:intersect).
      with(:id => [contact_data[:id]]).and_return(contacts)

    media = double('media')
    expect(media).to receive(:collect) {|&arg| [arg.call(medium)] }
    expect(Flapjack::Data::Medium).to receive(:intersect).
      with(:id => [medium.id]).and_return(media)

    expect(medium).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(email_data.reject {|k,v| :id.eql?(k)})

    expect(contact).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(contact_data.reject {|k,v| :id.eql?(k)})

    expect(acceptor).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(acceptor_data.reject {|k,v| :id.eql?(k)})

    get "/acceptors/#{acceptor.id}?include=contact.media"
    expect(last_response).to be_ok

    resp_data = acceptor_json(acceptor_data).merge(:relationships => acceptor_rel(acceptor_data))
    resp_data[:relationships][:contact][:data] = {:type => 'contact', :id => contact.id}

    resp_incl_contact = contact_json(contact_data).merge(:relationships => contact_rel(contact_data))
    resp_incl_contact[:relationships][:media][:data] = [{:type => 'medium', :id => medium.id}]

    resp_included = [
      resp_incl_contact,
      medium_json(email_data).merge(:relationships => medium_rel(email_data))
    ]

    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data => resp_data,
      :included => resp_included,
      :links => {:self  => "http://example.org/acceptors/#{acceptor.id}?include=contact.media"}
    ))
  end

  it "deletes an acceptor" do
    expect(Flapjack::Data::Acceptor).to receive(:lock).
      with(Flapjack::Data::Contact,
           Flapjack::Data::Medium,
           Flapjack::Data::Tag).
      and_yield

    expect(acceptor).to receive(:destroy)
    expect(Flapjack::Data::Acceptor).to receive(:find_by_id!).
      with(acceptor.id).and_return(acceptor)

    delete "/acceptors/#{acceptor.id}"
    expect(last_response.status).to eq(204)
  end

  it "deletes multiple acceptors" do
    expect(Flapjack::Data::Acceptor).to receive(:lock).
      with(Flapjack::Data::Contact,
           Flapjack::Data::Medium,
           Flapjack::Data::Tag).
      and_yield

    acceptors = double('acceptors')
    expect(acceptors).to receive(:count).and_return(2)
    expect(acceptors).to receive(:destroy_all)
    expect(Flapjack::Data::Acceptor).to receive(:intersect).
      with(:id => [acceptor.id, acceptor_2.id]).and_return(acceptors)

    delete "/acceptors",
      Flapjack.dump_json(:data => [
        {:id => acceptor.id, :type => 'acceptor'},
        {:id => acceptor_2.id, :type => 'acceptor'}
      ]),
      jsonapi_bulk_env
    expect(last_response.status).to eq(204)
  end

  it "does not delete an acceptor that does not exist" do
    expect(Flapjack::Data::Acceptor).to receive(:lock).
      with(Flapjack::Data::Contact,
           Flapjack::Data::Medium,
           Flapjack::Data::Tag).
      and_yield

    expect(Flapjack::Data::Acceptor).to receive(:find_by_id!).
      with(acceptor.id).and_raise(Zermelo::Records::Errors::RecordNotFound.new(Flapjack::Data::Acceptor, acceptor.id))

    delete "/acceptors/#{acceptor.id}"
    expect(last_response).to be_not_found
  end

end
