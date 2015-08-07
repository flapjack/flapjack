require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::BlackholeLinks', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:blackhole)    { double(Flapjack::Data::Blackhole, :id => blackhole_data[:id]) }
  let(:contact) { double(Flapjack::Data::Contact, :id => contact_data[:id]) }
  let(:tag)     { double(Flapjack::Data::Tag, :id => tag_data[:name]) }
  let(:medium)  { double(Flapjack::Data::Medium, :id => sms_data[:id]) }

  let(:blackhole_tags)  { double('blackhole_tags') }
  let(:blackhole_media) { double('blackhole_media') }

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

  it 'shows the contact for a blackhole' do
    expect(Flapjack::Data::Blackhole).to receive(:lock).
      with(Flapjack::Data::Contact).and_yield

    expect(blackhole).to receive(:contact).and_return(contact)

    blackholes = double('blackhole', :all => [blackhole])
    expect(blackholes).to receive(:empty?).and_return(false)
    expect(Flapjack::Data::Blackhole).to receive(:intersect).
      with(:id => blackhole.id).and_return(blackholes)

    get "/blackholes/#{blackhole.id}/contact"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => {:type => 'contact', :id => contact.id},
      :links => {
        :self    => "http://example.org/blackholes/#{blackhole.id}/relationships/contact",
        :related => "http://example.org/blackholes/#{blackhole.id}/contact",
      }
    ))
  end

  it 'cannot change the contact for a blackhole' do
    patch "/blackholes/#{blackhole.id}/relationships/contact", Flapjack.dump_json(:data => {
      :type => 'contact', :id => contact.id
    }), jsonapi_env
    expect(last_response.status).to eq(404)
  end

  it 'adds a medium to a blackhole' do
    expect(Flapjack::Data::Blackhole).to receive(:lock).
      with(Flapjack::Data::Medium).and_yield

    expect(Flapjack::Data::Blackhole).to receive(:find_by_id!).with(blackhole.id).
      and_return(blackhole)

    expect(blackhole_media).to receive(:add_ids).with(medium.id)
    expect(blackhole).to receive(:media).and_return(blackhole_media)

    post "/blackholes/#{blackhole.id}/relationships/media", Flapjack.dump_json(:data => [{
      :type => 'medium', :id => medium.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'lists media for a blackhole' do
    expect(Flapjack::Data::Blackhole).to receive(:lock).
      with(Flapjack::Data::Medium).and_yield

    sorted = double('sorted')
    paged  = double('paged')
    expect(paged).to receive(:ids).and_return([medium.id])
    expect(sorted).to receive(:page).with(1, :per_page => 20).and_return(paged)
    expect(sorted).to receive(:count).and_return(1)
    expect(blackhole_media).to receive(:sort).with(:id => :asc).and_return(sorted)
    expect(blackhole).to receive(:media).and_return(blackhole_media)

    blackholes = double('blackhole', :all => [blackhole])
    expect(blackholes).to receive(:empty?).and_return(false)
    expect(Flapjack::Data::Blackhole).to receive(:intersect).
      with(:id => blackhole.id).and_return(blackholes)

    get "/blackholes/#{blackhole.id}/media"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => [{:type => 'medium', :id => medium.id}],
      :links => {
        :self    => "http://example.org/blackholes/#{blackhole.id}/relationships/media",
        :related => "http://example.org/blackholes/#{blackhole.id}/media",
      },
      :meta => meta
    ))
  end

  it 'updates media for a blackhole' do
    expect(Flapjack::Data::Blackhole).to receive(:lock).
      with(Flapjack::Data::Medium).and_yield

    expect(Flapjack::Data::Blackhole).to receive(:find_by_id!).with(blackhole.id).
      and_return(blackhole)

    expect(blackhole_media).to receive(:ids).and_return([])
    expect(blackhole_media).to receive(:add_ids).with(medium.id)
    expect(blackhole).to receive(:media).twice.and_return(blackhole_media)

    patch "/blackholes/#{blackhole.id}/relationships/media", Flapjack.dump_json(:data => [{
      :type => 'medium', :id => medium.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'deletes a medium from a blackhole' do
    expect(Flapjack::Data::Blackhole).to receive(:lock).
      with(Flapjack::Data::Medium).and_yield

    expect(Flapjack::Data::Blackhole).to receive(:find_by_id!).with(blackhole.id).
      and_return(blackhole)

    expect(blackhole_media).to receive(:remove_ids).with(medium.id)
    expect(blackhole).to receive(:media).and_return(blackhole_media)

    delete "/blackholes/#{blackhole.id}/relationships/media", Flapjack.dump_json(:data => [{
      :type => 'medium', :id => medium.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'adds tags to a blackhole' do
    expect(Flapjack::Data::Blackhole).to receive(:lock).
      with(Flapjack::Data::Tag).and_yield

    expect(Flapjack::Data::Blackhole).to receive(:find_by_id!).with(blackhole.id).
      and_return(blackhole)

    expect(blackhole_tags).to receive(:add_ids).with(tag.id)
    expect(blackhole).to receive(:tags).and_return(blackhole_tags)

    post "/blackholes/#{blackhole.id}/relationships/tags", Flapjack.dump_json(:data => [{
      :type => 'tag', :id => tag.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'lists tags for a blackhole' do
    expect(Flapjack::Data::Blackhole).to receive(:lock).
      with(Flapjack::Data::Tag).and_yield

    sorted = double('sorted')
    paged  = double('paged')
    expect(paged).to receive(:ids).and_return([tag.id])
    expect(sorted).to receive(:page).with(1, :per_page => 20).and_return(paged)
    expect(sorted).to receive(:count).and_return(1)
    expect(blackhole_tags).to receive(:sort).with(:id => :asc).and_return(sorted)
    expect(blackhole).to receive(:tags).and_return(blackhole_tags)

    blackholes = double('blackhole', :all => [blackhole])
    expect(blackholes).to receive(:empty?).and_return(false)
    expect(Flapjack::Data::Blackhole).to receive(:intersect).
      with(:id => blackhole.id).and_return(blackholes)

    get "/blackholes/#{blackhole.id}/tags"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => [{:type => 'tag', :id => tag.id}],
      :links => {
        :self    => "http://example.org/blackholes/#{blackhole.id}/relationships/tags",
        :related => "http://example.org/blackholes/#{blackhole.id}/tags",
      },
      :meta => meta
    ))
  end

  it 'updates tags for a blackhole' do
    expect(Flapjack::Data::Blackhole).to receive(:lock).
      with(Flapjack::Data::Tag).and_yield

    expect(Flapjack::Data::Blackhole).to receive(:find_by_id!).with(blackhole.id).
      and_return(blackhole)

    expect(blackhole_tags).to receive(:ids).and_return([])
    expect(blackhole_tags).to receive(:add_ids).with(tag.id)
    expect(blackhole).to receive(:tags).twice.and_return(blackhole_tags)

    patch "/blackholes/#{blackhole.id}/relationships/tags", Flapjack.dump_json(:data => [{
      :type => 'tag', :id => tag.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'deletes a tag from a blackhole' do
    expect(Flapjack::Data::Blackhole).to receive(:lock).
      with(Flapjack::Data::Tag).and_yield

    expect(Flapjack::Data::Blackhole).to receive(:find_by_id!).with(blackhole.id).
      and_return(blackhole)

    expect(blackhole_tags).to receive(:remove_ids).with(tag.id)
    expect(blackhole).to receive(:tags).and_return(blackhole_tags)

    delete "/blackholes/#{blackhole.id}/relationships/tags", Flapjack.dump_json(:data => [{
      :type => 'tag', :id => tag.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

end
