require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::Media', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:medium)   { double(Flapjack::Data::Medium, :id => email_data[:id]) }
  let(:medium_2) { double(Flapjack::Data::Medium, :id => sms_data[:id]) }

  let(:contact)  { double(Flapjack::Data::Contact, :id => contact_data[:id]) }

  it "creates a medium" do
    expect(Flapjack::Data::Medium).to receive(:lock).
      with(Flapjack::Data::Contact, Flapjack::Data::Rule).and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    full_ids = double('full_ids')
    expect(full_ids).to receive(:associated_ids_for).with(:contact).and_return({medium.id => nil})
    expect(full_ids).to receive(:associated_ids_for).with(:rules).and_return({medium.id => []})
    expect(Flapjack::Data::Medium).to receive(:intersect).
      with(:id => [email_data[:id]]).exactly(3).times.and_return(empty_ids, full_ids, full_ids)

    expect(medium).to receive(:invalid?).and_return(false)
    expect(medium).to receive(:save).and_return(true)
    expect(Flapjack::Data::Medium).to receive(:new).with(email_data).
      and_return(medium)

    expect(medium).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(email_data)

    post "/media", Flapjack.dump_json(:media => email_data), jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json(:media => email_data.merge(:links =>
    {
      :contact => nil,
      :rules  => []
    })))

  end

  it "does not create a medium if the data is improperly formatted" do
    expect(Flapjack::Data::Medium).to receive(:lock).
      with(Flapjack::Data::Contact, Flapjack::Data::Rule).and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Medium).to receive(:intersect).
      with(:id => [email_data[:id]]).and_return(empty_ids)

    errors = double('errors', :full_messages => ['err'])
    expect(medium).to receive(:errors).and_return(errors)

    expect(medium).to receive(:invalid?).and_return(true)
    expect(medium).not_to receive(:save)
    expect(Flapjack::Data::Medium).to receive(:new).with(email_data).
      and_return(medium)

    post "/media", Flapjack.dump_json(:media => email_data), jsonapi_post_env
    expect(last_response.status).to eq(403)
    # TODO error body
  end

  it 'creates a medium with a linked contact' do
    expect(Flapjack::Data::Medium).to receive(:lock).
      with(Flapjack::Data::Contact, Flapjack::Data::Rule).and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    full_ids = double('full_ids')
    expect(full_ids).to receive(:associated_ids_for).with(:contact).and_return({medium.id => contact.id})
    expect(full_ids).to receive(:associated_ids_for).with(:rules).and_return({medium.id => []})
    expect(Flapjack::Data::Medium).to receive(:intersect).
      with(:id => [email_data[:id]]).exactly(3).times.and_return(empty_ids, full_ids, full_ids)

    expect(Flapjack::Data::Contact).to receive(:find_by_id!).with(contact_data[:id]).
      and_return(contact)

    expect(medium).to receive(:invalid?).and_return(false)
    expect(medium).to receive(:save).and_return(true)
    expect(medium).to receive(:contact=).with(contact)
    expect(Flapjack::Data::Medium).to receive(:new).with(email_data).
      and_return(medium)

    expect(medium).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(email_data)

    post "/media", Flapjack.dump_json(:media => email_data.merge(:links => {
      :contact => contact.id
    })), jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json(:links => {
        'media.contact' => 'http://example.org/contacts/{media.contact}',
      },
      :media => email_data.merge(:links => {
        :contact => contact.id,
        :rules => []
      }
    )))
  end

  it "does not create a medium with a linked contact if the contact doesn't exist" do
    expect(Flapjack::Data::Medium).to receive(:lock).
      with(Flapjack::Data::Contact, Flapjack::Data::Rule).and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Medium).to receive(:intersect).
      with(:id => [email_data[:id]]).and_return(empty_ids)

    email_with_contact_data = email_data.merge(:links => {
      :contact => contact_data[:id]
    })

    expect(Flapjack::Data::Contact).to receive(:find_by_id!).with(contact_data[:id]).
      and_raise(Zermelo::Records::Errors::RecordNotFound.new(Flapjack::Data::Contact, contact_data[:id]))

    expect(medium).to receive(:invalid?).and_return(false)
    expect(medium).not_to receive(:save)
    expect(medium).not_to receive(:contact=).with(contact)
    expect(Flapjack::Data::Medium).to receive(:new).with(email_data).
      and_return(medium)

    expect(Flapjack::Data::Medium).not_to receive(:as_jsonapi)

    post "/media", Flapjack.dump_json(:media => email_with_contact_data), jsonapi_post_env
    expect(last_response.status).to eq(404)
  end

  it "returns a single medium" do
    expect(Flapjack::Data::Medium).to receive(:find_by_id!).
      with(medium.id).and_return(medium)

    full_ids = double('full_ids')
    expect(full_ids).to receive(:associated_ids_for).with(:contact).and_return({medium.id => nil})
    expect(full_ids).to receive(:associated_ids_for).with(:rules).and_return({medium.id => []})
    expect(Flapjack::Data::Medium).to receive(:intersect).
      with(:id => [medium.id]).twice.and_return(full_ids)

    expect(medium).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(email_data)

    get "/media/#{medium.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:media => email_data.merge(:links => {
      :contact => nil,
      :rules => []
    })))
  end

  it "returns all media" do
    meta = {
      :pagination => {
        :page        => 1,
        :per_page    => 20,
        :total_pages => 1,
        :total_count => 1
      }
    }

    expect(Flapjack::Data::Medium).to receive(:count).and_return(1)

    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).
      and_return([medium])
    expect(Flapjack::Data::Medium).to receive(:sort).
      with(:id).and_return(sorted)

    full_ids = double('full_ids')
    expect(full_ids).to receive(:associated_ids_for).with(:contact).and_return({medium.id => nil})
    expect(full_ids).to receive(:associated_ids_for).with(:rules).and_return({medium.id => []})
    expect(Flapjack::Data::Medium).to receive(:intersect).
      with(:id => [medium.id]).twice.and_return(full_ids)

    expect(medium).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(email_data)

    get '/media'
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:media => [email_data.merge(:links => {
      :contact => nil,
      :rules => []
    })], :meta => meta))
  end

  it "does not return a medium if the medium is not present" do
    expect(Flapjack::Data::Medium).to receive(:find_by_id!).with(medium.id).
      and_raise(Zermelo::Records::Errors::RecordNotFound.new(Flapjack::Data::Medium, medium.id))

    get "/media/#{medium.id}"
    expect(last_response).to be_not_found
  end

  it "updates a medium" do
    expect(Flapjack::Data::Medium).to receive(:find_by_ids!).
      with(medium.id).and_return([medium])

    expect(medium).to receive(:address=).with('12345')
    expect(medium).to receive(:invalid?).and_return(false)
    expect(medium).to receive(:save).and_return(true)

    put "/media/#{medium.id}",
      Flapjack.dump_json(:media => {:id => medium.id, :address => '12345'}),
      jsonapi_put_env
    expect(last_response.status).to eq(204)
  end

  it "updates multiple media" do
    expect(Flapjack::Data::Medium).to receive(:find_by_ids!).
      with(medium.id, medium_2.id).and_return([medium, medium_2])

    expect(medium).to receive(:address=).with('12345')
    expect(medium).to receive(:invalid?).and_return(false)
    expect(medium).to receive(:save).and_return(true)

    expect(medium_2).to receive(:interval=).with(120)
    expect(medium_2).to receive(:invalid?).and_return(false)
    expect(medium_2).to receive(:save).and_return(true)

    put "/media/#{medium.id},#{medium_2.id}",
      Flapjack.dump_json(:media => [
        {:id => medium.id, :address => '12345'},
        {:id => medium_2.id, :interval => 120}
      ]),
      jsonapi_put_env
    expect(last_response.status).to eq(204)
  end

  it "does not update a medium that's not present" do
    expect(Flapjack::Data::Medium).to receive(:find_by_ids!).
      with(medium.id).and_raise(Zermelo::Records::Errors::RecordsNotFound.new(Flapjack::Data::Medium, [medium.id]))

    put "/media/#{medium.id}",
      Flapjack.dump_json(:media => {:id => medium.id, :address => '12345'}),
      jsonapi_put_env
    expect(last_response.status).to eq(404)
  end

  it "deletes a medium" do
    media = double('media')
    expect(media).to receive(:ids).and_return([medium.id])
    expect(media).to receive(:destroy_all)
    expect(Flapjack::Data::Medium).to receive(:intersect).
      with(:id => [medium.id]).and_return(media)

    delete "/media/#{medium.id}"
    expect(last_response.status).to eq(204)
  end

  it "deletes multiple media" do
    media = double('media')
    expect(media).to receive(:ids).and_return([medium.id, medium_2.id])
    expect(media).to receive(:destroy_all)
    expect(Flapjack::Data::Medium).to receive(:intersect).
      with(:id => [medium.id, medium_2.id]).and_return(media)

    delete "/media/#{medium.id},#{medium_2.id}"
    expect(last_response.status).to eq(204)
  end

  it "does not delete a medium that's not found" do
    media = double('media')
    expect(media).to receive(:ids).and_return([])
    expect(media).not_to receive(:destroy_all)
    expect(Flapjack::Data::Medium).to receive(:intersect).
      with(:id => [medium.id]).and_return(media)

    delete "/media/#{medium.id}"
    expect(last_response).to be_not_found
  end
end
