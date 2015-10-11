require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::Media', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:medium)   { double(Flapjack::Data::Medium, :id => email_data[:id]) }
  let(:medium_2) { double(Flapjack::Data::Medium, :id => sms_data[:id]) }

  let(:contact)  { double(Flapjack::Data::Contact, :id => contact_data[:id]) }

  it "creates a medium" do
    expect(Flapjack::Data::Medium).to receive(:lock).
      with(no_args).
      and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Medium).to receive(:intersect).
      with(:id => [email_data[:id]]).and_return(empty_ids)

    expect(medium).to receive(:invalid?).and_return(false)
    expect(medium).to receive(:save!).and_return(true)
    expect(Flapjack::Data::Medium).to receive(:new).with(email_data).
      and_return(medium)

    expect(medium).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(email_data.reject {|k,v| :id.eql?(k)})

    req_data = medium_json(email_data)
    resp_data = req_data.merge(:relationships => medium_rel(email_data))

    post "/media", Flapjack.dump_json(:data => req_data), jsonapi_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data =>
      resp_data))
  end

  it "does not create a medium if the data is improperly formatted" do
    expect(Flapjack::Data::Medium).to receive(:lock).
      with(no_args).
      and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Medium).to receive(:intersect).
      with(:id => [email_data[:id]]).and_return(empty_ids)

    errors = double('errors', :full_messages => ['err'])
    expect(medium).to receive(:errors).and_return(errors)

    expect(medium).to receive(:invalid?).and_return(true)
    expect(medium).not_to receive(:save!)
    expect(Flapjack::Data::Medium).to receive(:new).with(email_data).
      and_return(medium)

    req_data = medium_json(email_data)

    post "/media", Flapjack.dump_json(:data => req_data), jsonapi_env
    expect(last_response.status).to eq(403)
    # TODO error body
  end

  it "returns a single medium" do
    expect(Flapjack::Data::Medium).to receive(:lock).
      with(no_args).
      and_yield

    expect(Flapjack::Data::Medium).to receive(:intersect).
      with(:id => Set.new([medium.id])).and_return([medium])

    expect(medium).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(email_data.reject {|k,v| :id.eql?(k)})

    resp_data = medium_json(email_data).merge(:relationships => medium_rel(email_data))

    get "/media/#{medium.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data =>
      resp_data, :links => {:self  => "http://example.org/media/#{medium.id}"}))
  end

  it "returns all media" do
    expect(Flapjack::Data::Medium).to receive(:lock).
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
      :self  => 'http://example.org/media',
      :first => 'http://example.org/media?page=1',
      :last  => 'http://example.org/media?page=1'
    }

    page = double('page')
    expect(page).to receive(:empty?).and_return(false)
    expect(page).to receive(:ids).and_return([medium.id])
    expect(page).to receive(:collect) {|&arg| [arg.call(medium)] }
    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).
      and_return(page)
    expect(sorted).to receive(:count).and_return(1)
    expect(Flapjack::Data::Medium).to receive(:sort).
      with(:id).and_return(sorted)

    expect(medium).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(email_data.reject {|k,v| :id.eql?(k)})

    resp_data = [medium_json(email_data).merge(:relationships => medium_rel(email_data))]

    get '/media'
    expect(last_response).to be_ok
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data => resp_data,
      :links => links, :meta => meta))
  end

  it "does not return a medium if the medium is not present" do
    expect(Flapjack::Data::Medium).to receive(:lock).
      with(no_args).
      and_yield

    no_media = double('no_media')
    expect(no_media).to receive(:empty?).and_return(true)

    expect(Flapjack::Data::Medium).to receive(:intersect).
      with(:id => Set.new([medium.id])).and_return(no_media)

    get "/media/#{medium.id}"
    expect(last_response).to be_not_found
  end

  it "updates a medium" do
    expect(Flapjack::Data::Medium).to receive(:lock).
      with(no_args).
      and_yield

    expect(Flapjack::Data::Medium).to receive(:find_by_id!).
      with(medium.id).and_return(medium)

    expect(medium).to receive(:address=).with('12345')
    expect(medium).to receive(:invalid?).and_return(false)
    expect(medium).to receive(:save!).and_return(true)

    patch "/media/#{medium.id}",
      Flapjack.dump_json(:data => {:id => medium.id, :type => 'medium', :attributes => {:address => '12345'}}),
      jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it "updates multiple media" do
    expect(Flapjack::Data::Medium).to receive(:lock).
      with(no_args).
      and_yield

    expect(Flapjack::Data::Medium).to receive(:find_by_ids!).
      with(medium.id, medium_2.id).and_return([medium, medium_2])

    expect(medium).to receive(:address=).with('12345')
    expect(medium).to receive(:invalid?).and_return(false)
    expect(medium).to receive(:save!).and_return(true)

    expect(medium_2).to receive(:interval=).with(120)
    expect(medium_2).to receive(:invalid?).and_return(false)
    expect(medium_2).to receive(:save!).and_return(true)

    patch "/media",
      Flapjack.dump_json(:data => [
        {:id => medium.id, :type => 'medium', :attributes => {:address => '12345'}},
        {:id => medium_2.id, :type => 'medium', :attributes => {:interval => 120}}
      ]),
      jsonapi_bulk_env
    expect(last_response.status).to eq(204)
  end

  it "does not update a medium that's not present" do
    expect(Flapjack::Data::Medium).to receive(:lock).
      with(no_args).
      and_yield

    expect(Flapjack::Data::Medium).to receive(:find_by_id!).
      with(medium.id).and_raise(Zermelo::Records::Errors::RecordNotFound.new(Flapjack::Data::Medium, medium.id))

    patch "/media/#{medium.id}",
      Flapjack.dump_json(:data => {:id => medium.id, :type => 'medium', :attributes => {:address => '12345'}}),
      jsonapi_env
    expect(last_response.status).to eq(404)
  end

  it "deletes a medium" do
    expect(Flapjack::Data::Medium).to receive(:lock).
      with(Flapjack::Data::Alert,
           Flapjack::Data::Check,
           Flapjack::Data::Contact,
           Flapjack::Data::Rule,
           Flapjack::Data::ScheduledMaintenance,
           Flapjack::Data::State).
      and_yield

    expect(medium).to receive(:destroy)
    expect(Flapjack::Data::Medium).to receive(:find_by_id!).
      with(medium.id).and_return(medium)

    delete "/media/#{medium.id}"
    expect(last_response.status).to eq(204)
  end

  it "deletes multiple media" do
    expect(Flapjack::Data::Medium).to receive(:lock).
      with(Flapjack::Data::Alert,
           Flapjack::Data::Check,
           Flapjack::Data::Contact,
           Flapjack::Data::Rule,
           Flapjack::Data::ScheduledMaintenance,
           Flapjack::Data::State).
      and_yield

    media = double('media')
    expect(media).to receive(:count).and_return(2)
    expect(media).to receive(:destroy_all)
    expect(Flapjack::Data::Medium).to receive(:intersect).
      with(:id => [medium.id, medium_2.id]).and_return(media)

    delete "/media",
      Flapjack.dump_json(:data => [
        {:id => medium.id, :type => 'medium'},
        {:id => medium_2.id, :type => 'medium'}
      ]),
      jsonapi_bulk_env
    expect(last_response.status).to eq(204)
  end

  it "does not delete a medium that's not found" do
    expect(Flapjack::Data::Medium).to receive(:lock).
      with(Flapjack::Data::Alert,
           Flapjack::Data::Check,
           Flapjack::Data::Contact,
           Flapjack::Data::Rule,
           Flapjack::Data::ScheduledMaintenance,
           Flapjack::Data::State).
      and_yield

    expect(Flapjack::Data::Medium).to receive(:find_by_id!).
      with(medium.id).and_raise(Zermelo::Records::Errors::RecordNotFound.new(Flapjack::Data::Medium, medium.id))

    delete "/media/#{medium.id}"
    expect(last_response).to be_not_found
  end
end
