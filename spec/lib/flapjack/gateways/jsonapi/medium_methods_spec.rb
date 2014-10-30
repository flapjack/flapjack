require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::MediumMethods', :sinatra => true, :logger => true do

  include_context "jsonapi"

  let(:medium) { double(Flapjack::Data::Medium, :id => "ab12") }

  let(:medium_data) {
    {:type => 'email',
     :address => 'abc@example.com',
     :interval => 120,
     :rollup_threshold => 3
    }
  }

  let(:contact)      { double(Flapjack::Data::Contact, :id => '21') }

  it "creates a medium" do
    expect(Flapjack::Data::Contact).to receive(:lock).
      with(Flapjack::Data::Medium).and_yield

    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id).and_return(contact)

    expect(medium).to receive(:invalid?).and_return(false)
    expect(medium).to receive(:save).and_return(true)
    expect(medium).to receive(:type).and_return(medium_data[:type])
    expect(Flapjack::Data::Medium).to receive(:new).
      with(medium_data.merge(:id => nil)).
      and_return(medium)

    no_media = double('no_media', :all => [])
    contact_media = ('contact_media')
    expect(contact_media).to receive(:intersect).
      with(:type => medium_data[:type]).and_return(no_media)
    expect(contact).to receive(:media).and_return(contact_media)

    expect(contact_media).to receive(:"<<").with(medium)

    post "/contacts/#{contact.id}/media", Flapjack.dump_json(:media => [medium_data]), jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json([medium.id]))
  end

  it "does not create a medium if the data is improperly formatted" do
    expect(Flapjack::Data::Contact).to receive(:lock).
      with(Flapjack::Data::Medium).and_yield

    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id).and_return(contact)

    errors = double('errors', :full_messages => ['err'])
    expect(medium).to receive(:errors).and_return(errors)

    expect(medium).to receive(:invalid?).and_return(true)
    expect(medium).not_to receive(:save)
    expect(Flapjack::Data::Medium).to receive(:new).and_return(medium)

    post "/contacts/#{contact.id}/media", Flapjack.dump_json(:media => [{'silly' => 'sausage'}]), jsonapi_post_env
    expect(last_response.status).to eq(403)
  end

  it "does not create a medium if the contact doesn't exist" do
    expect(Flapjack::Data::Contact).to receive(:lock).
      with(Flapjack::Data::Medium).and_yield

    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id).and_return(nil)

    post "/contacts/#{contact.id}/media", Flapjack.dump_json(:media => [medium_data]), jsonapi_post_env
    expect(last_response.status).to eq(403)
  end

  it "returns a single medium" do
    expect(Flapjack::Data::Medium).to receive(:find_by_ids!).
      with(medium.id).and_return([medium])

    expect(medium).to receive(:as_json).and_return(medium_data)

    media_ids = double('media_ids')
    expect(media_ids).to receive(:associated_ids_for).with(:contact).and_return(medium.id => contact.id)
    expect(media_ids).to receive(:associated_ids_for).with(:routes).and_return(medium.id => [])
    expect(Flapjack::Data::Medium).to receive(:intersect).with(:id => [medium.id]).
      exactly(2).times.and_return(media_ids)

    get "/media/#{medium.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:media => [medium_data]))
  end

  it "returns all media" do
    expect(Flapjack::Data::Medium).to receive(:count).and_return(1)

    meta = {:pagination => {
      :page        => 1,
      :per_page    => 20,
      :total_pages => 1,
      :total_count => 1
    }}

    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).
      and_return([medium])
    expect(Flapjack::Data::Medium).to receive(:sort).
      with(:id, :order => 'alpha').and_return(sorted)

    media_ids = double('media_ids')
    expect(media_ids).to receive(:associated_ids_for).with(:contact).
      and_return(medium.id => contact.id)
    expect(media_ids).to receive(:associated_ids_for).with(:routes).
      and_return(medium.id => [])
    expect(Flapjack::Data::Medium).to receive(:intersect).with(:id => [medium.id]).
      exactly(2).times.and_return(media_ids)

    expect(medium).to receive(:as_json).and_return(medium_data)

    get "/media"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:media => [medium_data], :meta => meta))
  end

  it "does not return a medium if the medium is not present" do
    expect(Flapjack::Data::Medium).to receive(:find_by_ids!).with(medium.id).
      and_raise(Sandstorm::Records::Errors::RecordsNotFound.new(Flapjack::Data::Medium, [medium.id]))

    get "/media/#{medium.id}"
    expect(last_response).to be_not_found
  end

  it "updates a medium" do
    expect(Flapjack::Data::Medium).to receive(:find_by_ids!).
      with(medium.id).and_return([medium])

    expect(medium).to receive(:address=).with('12345')
    expect(medium).to receive(:save).and_return(true)

    patch "/media/#{medium.id}",
      Flapjack.dump_json([{:op => 'replace', :path => '/media/0/address', :value => '12345'}]),
      jsonapi_patch_env
    expect(last_response.status).to eq(204)
  end

  it "updates multiple media" do
    medium_2 = double(Flapjack::Data::Medium, :id => 'uiop')
    expect(Flapjack::Data::Medium).to receive(:find_by_ids!).
      with(medium.id, medium_2.id).and_return([medium, medium_2])

    expect(medium).to receive(:interval=).with(80)
    expect(medium).to receive(:save).and_return(true)

    expect(medium_2).to receive(:interval=).with(80)
    expect(medium_2).to receive(:save).and_return(true)

    patch "/media/#{medium.id},#{medium_2.id}",
      Flapjack.dump_json([{:op => 'replace', :path => '/media/0/interval', :value => 80}]),
      jsonapi_patch_env
    expect(last_response.status).to eq(204)
  end

  it "does not update a medium that's not present" do
    expect(Flapjack::Data::Medium).to receive(:find_by_ids!).with(medium.id).
      and_raise(Sandstorm::Records::Errors::RecordsNotFound.new(Flapjack::Data::Medium, [medium.id]))

    patch "/media/#{medium.id}",
      Flapjack.dump_json([{:op => 'replace', :path => '/media/0/address', :value => 'xyz@example.com'}]),
      jsonapi_patch_env
    expect(last_response).to be_not_found
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
    expect(media).to receive(:ids).and_return([medium.id, '6789'])
    expect(media).to receive(:destroy_all)
    expect(Flapjack::Data::Medium).to receive(:intersect).
      with(:id => [medium.id, '6789']).and_return(media)

    delete "/media/#{medium.id},6789"
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
