require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::RejectorLinks', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:rejector)    { double(Flapjack::Data::Rejector, :id => rejector_data[:id]) }
  let(:contact) { double(Flapjack::Data::Contact, :id => contact_data[:id]) }
  let(:tag)     { double(Flapjack::Data::Tag, :id => tag_data[:name]) }
  let(:medium)  { double(Flapjack::Data::Medium, :id => sms_data[:id]) }

  let(:rejector_tags)  { double('rejector_tags') }
  let(:rejector_media) { double('rejector_media') }

  let(:meta) {
    {
      :pagination => {
        :page        => 1,
        :per_page    => 20,
        :total_pages => 1,
        :total_count => 1
      }
    }
  }

  it 'shows the contact for a rejector' do
    expect(Flapjack::Data::Rejector).to receive(:lock).
      with(Flapjack::Data::Contact).and_yield

    expect(rejector).to receive(:contact).and_return(contact)

    rejectors = double('rejector', :all => [rejector])
    expect(rejectors).to receive(:empty?).and_return(false)
    expect(Flapjack::Data::Rejector).to receive(:intersect).
      with(:id => rejector.id).and_return(rejectors)

    get "/rejectors/#{rejector.id}/contact"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => {:type => 'contact', :id => contact.id},
      :links => {
        :self    => "http://example.org/rejectors/#{rejector.id}/relationships/contact",
        :related => "http://example.org/rejectors/#{rejector.id}/contact",
      }
    ))
  end

  it 'cannot change the contact for a rejector' do
    patch "/rejectors/#{rejector.id}/relationships/contact", Flapjack.dump_json(:data => {
      :type => 'contact', :id => contact.id
    }), jsonapi_env
    expect(last_response.status).to eq(404)
  end

  it 'adds a medium to a rejector' do
    expect(Flapjack::Data::Rejector).to receive(:lock).
      with(Flapjack::Data::Medium).and_yield

    expect(Flapjack::Data::Rejector).to receive(:find_by_id!).with(rejector.id).
      and_return(rejector)

    expect(rejector_media).to receive(:add_ids).with(medium.id)
    expect(rejector).to receive(:media).and_return(rejector_media)

    post "/rejectors/#{rejector.id}/relationships/media", Flapjack.dump_json(:data => [{
      :type => 'medium', :id => medium.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'lists media for a rejector' do
    expect(Flapjack::Data::Rejector).to receive(:lock).
      with(Flapjack::Data::Medium).and_yield

    sorted = double('sorted')
    paged  = double('paged')
    expect(paged).to receive(:ids).and_return([medium.id])
    expect(sorted).to receive(:page).with(1, :per_page => 20).and_return(paged)
    expect(sorted).to receive(:count).and_return(1)
    expect(rejector_media).to receive(:sort).with(:id => :asc).and_return(sorted)
    expect(rejector).to receive(:media).and_return(rejector_media)

    rejectors = double('rejector', :all => [rejector])
    expect(rejectors).to receive(:empty?).and_return(false)
    expect(Flapjack::Data::Rejector).to receive(:intersect).
      with(:id => rejector.id).and_return(rejectors)

    get "/rejectors/#{rejector.id}/media"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => [{:type => 'medium', :id => medium.id}],
      :links => {
        :self    => "http://example.org/rejectors/#{rejector.id}/relationships/media",
        :related => "http://example.org/rejectors/#{rejector.id}/media",
      },
      :meta => meta
    ))
  end

  it 'updates media for a rejector' do
    expect(Flapjack::Data::Rejector).to receive(:lock).
      with(Flapjack::Data::Medium).and_yield

    expect(Flapjack::Data::Rejector).to receive(:find_by_id!).with(rejector.id).
      and_return(rejector)

    expect(rejector_media).to receive(:ids).and_return([])
    expect(rejector_media).to receive(:add_ids).with(medium.id)
    expect(rejector).to receive(:media).twice.and_return(rejector_media)

    patch "/rejectors/#{rejector.id}/relationships/media", Flapjack.dump_json(:data => [{
      :type => 'medium', :id => medium.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'deletes a medium from a rejector' do
    expect(Flapjack::Data::Rejector).to receive(:lock).
      with(Flapjack::Data::Medium).and_yield

    expect(Flapjack::Data::Rejector).to receive(:find_by_id!).with(rejector.id).
      and_return(rejector)

    expect(rejector_media).to receive(:remove_ids).with(medium.id)
    expect(rejector).to receive(:media).and_return(rejector_media)

    delete "/rejectors/#{rejector.id}/relationships/media", Flapjack.dump_json(:data => [{
      :type => 'medium', :id => medium.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'adds tags to a rejector' do
    expect(Flapjack::Data::Rejector).to receive(:lock).
      with(Flapjack::Data::Tag).and_yield

    expect(Flapjack::Data::Rejector).to receive(:find_by_id!).with(rejector.id).
      and_return(rejector)

    expect(rejector_tags).to receive(:add_ids).with(tag.id)
    expect(rejector).to receive(:tags).and_return(rejector_tags)

    post "/rejectors/#{rejector.id}/relationships/tags", Flapjack.dump_json(:data => [{
      :type => 'tag', :id => tag.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'lists tags for a rejector' do
    expect(Flapjack::Data::Rejector).to receive(:lock).
      with(Flapjack::Data::Tag).and_yield

    sorted = double('sorted')
    paged  = double('paged')
    expect(paged).to receive(:ids).and_return([tag.id])
    expect(sorted).to receive(:page).with(1, :per_page => 20).and_return(paged)
    expect(sorted).to receive(:count).and_return(1)
    expect(rejector_tags).to receive(:sort).with(:id => :asc).and_return(sorted)
    expect(rejector).to receive(:tags).and_return(rejector_tags)

    rejectors = double('rejector', :all => [rejector])
    expect(rejectors).to receive(:empty?).and_return(false)
    expect(Flapjack::Data::Rejector).to receive(:intersect).
      with(:id => rejector.id).and_return(rejectors)

    get "/rejectors/#{rejector.id}/tags"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => [{:type => 'tag', :id => tag.id}],
      :links => {
        :self    => "http://example.org/rejectors/#{rejector.id}/relationships/tags",
        :related => "http://example.org/rejectors/#{rejector.id}/tags",
      },
      :meta => meta
    ))
  end

  it 'updates tags for a rejector' do
    expect(Flapjack::Data::Rejector).to receive(:lock).
      with(Flapjack::Data::Tag).and_yield

    expect(Flapjack::Data::Rejector).to receive(:find_by_id!).with(rejector.id).
      and_return(rejector)

    expect(rejector_tags).to receive(:ids).and_return([])
    expect(rejector_tags).to receive(:add_ids).with(tag.id)
    expect(rejector).to receive(:tags).twice.and_return(rejector_tags)

    patch "/rejectors/#{rejector.id}/relationships/tags", Flapjack.dump_json(:data => [{
      :type => 'tag', :id => tag.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'deletes a tag from a rejector' do
    expect(Flapjack::Data::Rejector).to receive(:lock).
      with(Flapjack::Data::Tag).and_yield

    expect(Flapjack::Data::Rejector).to receive(:find_by_id!).with(rejector.id).
      and_return(rejector)

    expect(rejector_tags).to receive(:remove_ids).with(tag.id)
    expect(rejector).to receive(:tags).and_return(rejector_tags)

    delete "/rejectors/#{rejector.id}/relationships/tags", Flapjack.dump_json(:data => [{
      :type => 'tag', :id => tag.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

end
