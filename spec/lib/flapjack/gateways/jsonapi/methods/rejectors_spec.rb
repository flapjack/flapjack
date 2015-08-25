require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::Rejectors', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:rejector)    { double(Flapjack::Data::Rejector, :id => rejector_data[:id]) }
  let(:rejector_2)  { double(Flapjack::Data::Rejector, :id => rejector_2_data[:id]) }

  let(:contact) { double(Flapjack::Data::Contact, :id => contact_data[:id]) }

  let(:medium)  { double(Flapjack::Data::Medium, :id => email_data[:id]) }

  it "creates a rejector" do
    expect(Flapjack::Data::Rejector).to receive(:lock).
      with(no_args).
      and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Rejector).to receive(:intersect).
      with(:id => [rejector_data[:id]]).and_return(empty_ids)

    expect(rejector).to receive(:invalid?).and_return(false)
    expect(rejector).to receive(:save!).and_return(true)
    expect(Flapjack::Data::Rejector).to receive(:new).with(rejector_data).
      and_return(rejector)

    expect(rejector).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(rejector_data.reject {|k,v| :id.eql?(k)})

    req_data  = rejector_json(rejector_data)
    resp_data = req_data.merge(:relationships => rejector_rel(rejector_data))

    post "/rejectors", Flapjack.dump_json(:data => req_data), jsonapi_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data =>
      resp_data))
  end

  it "does not create a rejector if the data is improperly formatted" do
    expect(Flapjack::Data::Rejector).to receive(:lock).
      with(no_args).
      and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Rejector).to receive(:intersect).
      with(:id => [rejector_data[:id]]).and_return(empty_ids)

    errors = double('errors', :full_messages => ['err'])
    expect(rejector).to receive(:errors).and_return(errors)

    expect(rejector).to receive(:invalid?).and_return(true)
    expect(rejector).not_to receive(:save!)
    expect(Flapjack::Data::Rejector).to receive(:new).with(rejector_data).
      and_return(rejector)

    req_data  = rejector_json(rejector_data)

    post "/rejectors", Flapjack.dump_json(:data => req_data), jsonapi_env
    expect(last_response.status).to eq(403)
  end

  it "gets all rejectors" do
    expect(Flapjack::Data::Rejector).to receive(:lock).
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
      :self  => 'http://example.org/rejectors',
      :first => 'http://example.org/rejectors?page=1',
      :last  => 'http://example.org/rejectors?page=1'
    }

    page = double('page')
    expect(page).to receive(:empty?).and_return(false)
    expect(page).to receive(:ids).and_return([rejector.id])
    expect(page).to receive(:collect) {|&arg| [arg.call(rejector)] }
    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).
      and_return(page)
    expect(sorted).to receive(:count).and_return(1)
    expect(Flapjack::Data::Rejector).to receive(:sort).
      with(:id).and_return(sorted)

    expect(rejector).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(rejector_data.reject {|k,v| :id.eql?(k)})

    resp_data = [rejector_json(rejector_data).merge(:relationships => rejector_rel(rejector_data))]

    get '/rejectors'
    expect(last_response).to be_ok
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data => resp_data,
      :links => links, :meta => meta))
  end

  it "gets a single rejector" do
    expect(Flapjack::Data::Rejector).to receive(:lock).
      with(no_args).
      and_yield

    expect(Flapjack::Data::Rejector).to receive(:intersect).
      with(:id => Set.new([rejector.id])).and_return([rejector])

    expect(rejector).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(rejector_data.reject {|k,v| :id.eql?(k)})

    resp_data = rejector_json(rejector_data).merge(:relationships => rejector_rel(rejector_data))

    get "/rejectors/#{rejector.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data =>
      resp_data, :links => {:self  => "http://example.org/rejectors/#{rejector.id}"}))
  end

  it "does not get a rejector that does not exist" do
    expect(Flapjack::Data::Rejector).to receive(:lock).
      with(no_args).
      and_yield

    no_rejectors = double('no_rejectors')
    expect(no_rejectors).to receive(:empty?).and_return(true)

    expect(Flapjack::Data::Rejector).to receive(:intersect).
      with(:id => Set.new([rejector.id])).and_return(no_rejectors)

    get "/rejectors/#{rejector.id}"
    expect(last_response).to be_not_found
  end

  it "retrieves a rejector and its linked contact record" do
    expect(Flapjack::Data::Rejector).to receive(:lock).
      with(Flapjack::Data::Contact).
      and_yield

    rejectors = double('rejectors')
    expect(rejectors).to receive(:empty?).and_return(false)
    expect(rejectors).to receive(:collect) {|&arg| [arg.call(rejector)] }
    expect(rejectors).to receive(:associated_ids_for).with(:contact).
      and_return(rejector.id => contact.id)
    expect(rejectors).to receive(:ids).and_return(Set.new([rejector.id]))
    expect(Flapjack::Data::Rejector).to receive(:intersect).
      with(:id => Set.new([rejector.id])).twice.and_return(rejectors)

    contacts = double('contacts')
    expect(contacts).to receive(:collect) {|&arg| [arg.call(contact)] }
    expect(Flapjack::Data::Contact).to receive(:intersect).
      with(:id => [contact.id]).and_return(contacts)

    expect(contact).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(contact_data.reject {|k,v| :id.eql?(k)})

    expect(rejector).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(rejector_data.reject {|k,v| :id.eql?(k)})

    get "/rejectors/#{rejector.id}?include=contact"
    expect(last_response).to be_ok

    resp_data = rejector_json(rejector_data).merge(:relationships => rejector_rel(rejector_data))
    resp_data[:relationships][:contact][:data] = {:type => 'contact', :id => contact.id}

    resp_included = [contact_json(contact_data).merge(:relationships => contact_rel(contact_data))]

    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data => resp_data,
      :included => resp_included,
      :links => {:self  => "http://example.org/rejectors/#{rejector.id}?include=contact"}))
  end

  it "retrieves a rejector, its contact, and all of its contact's media records" do
    expect(Flapjack::Data::Rejector).to receive(:lock).
      with(Flapjack::Data::Contact,
           Flapjack::Data::Medium).
      and_yield

    rejectors = double('rejectors')
    expect(rejectors).to receive(:empty?).and_return(false)
    expect(rejectors).to receive(:collect) {|&arg| [arg.call(rejector)] }
    expect(rejectors).to receive(:associated_ids_for).with(:contact).
      and_return(rejector.id => contact.id)
    expect(rejectors).to receive(:ids).and_return(Set.new([rejector.id]))
    expect(Flapjack::Data::Rejector).to receive(:intersect).
      with(:id => Set.new([rejector.id])).twice.and_return(rejectors)

    contacts = double('contacts')
    expect(contacts).to receive(:collect) {|&arg| [arg.call(contact)] }
    expect(contacts).to receive(:associated_ids_for).with(:media).
      and_return({contact.id => [medium.id]})
    expect(Flapjack::Data::Contact).to receive(:intersect).
      with(:id => [contact_data[:id]]).twice.and_return(contacts)

    media = double('media')
    expect(media).to receive(:collect) {|&arg| [arg.call(medium)] }
    expect(Flapjack::Data::Medium).to receive(:intersect).
      with(:id => [medium.id]).and_return(media)

    expect(medium).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(email_data.reject {|k,v| :id.eql?(k)})

    expect(contact).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(contact_data.reject {|k,v| :id.eql?(k)})

    expect(rejector).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(rejector_data.reject {|k,v| :id.eql?(k)})

    get "/rejectors/#{rejector.id}?include=contact.media"
    expect(last_response).to be_ok

    resp_data = rejector_json(rejector_data).merge(:relationships => rejector_rel(rejector_data))
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
      :links => {:self  => "http://example.org/rejectors/#{rejector.id}?include=contact.media"}
    ))
  end

  it "deletes a rejector" do
    expect(Flapjack::Data::Rejector).to receive(:lock).
      with(Flapjack::Data::Contact,
           Flapjack::Data::Medium,
           Flapjack::Data::Tag).
      and_yield

    expect(rejector).to receive(:destroy)
    expect(Flapjack::Data::Rejector).to receive(:find_by_id!).
      with(rejector.id).and_return(rejector)

    delete "/rejectors/#{rejector.id}"
    expect(last_response.status).to eq(204)
  end

  it "deletes multiple rejectors" do
    expect(Flapjack::Data::Rejector).to receive(:lock).
      with(Flapjack::Data::Contact,
           Flapjack::Data::Medium,
           Flapjack::Data::Tag).
      and_yield

    rejectors = double('rejectors')
    expect(rejectors).to receive(:count).and_return(2)
    expect(rejectors).to receive(:destroy_all)
    expect(Flapjack::Data::Rejector).to receive(:intersect).
      with(:id => [rejector.id, rejector_2.id]).and_return(rejectors)

    delete "/rejectors",
      Flapjack.dump_json(:data => [
        {:id => rejector.id, :type => 'rejector'},
        {:id => rejector_2.id, :type => 'rejector'}
      ]),
      jsonapi_bulk_env
    expect(last_response.status).to eq(204)
  end

  it "does not delete a rejector that does not exist" do
    expect(Flapjack::Data::Rejector).to receive(:lock).
      with(Flapjack::Data::Contact,
           Flapjack::Data::Medium,
           Flapjack::Data::Tag).
      and_yield

    expect(Flapjack::Data::Rejector).to receive(:find_by_id!).
      with(rejector.id).and_raise(Zermelo::Records::Errors::RecordNotFound.new(Flapjack::Data::Rejector, rejector.id))

    delete "/rejectors/#{rejector.id}"
    expect(last_response).to be_not_found
  end

end
