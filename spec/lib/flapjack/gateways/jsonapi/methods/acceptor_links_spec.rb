require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::AcceptorLinks', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:acceptor)    { double(Flapjack::Data::Acceptor, :id => acceptor_data[:id]) }
  let(:contact) { double(Flapjack::Data::Contact, :id => contact_data[:id]) }
  let(:tag)     { double(Flapjack::Data::Tag, :id => tag_data[:name]) }
  let(:medium)  { double(Flapjack::Data::Medium, :id => sms_data[:id]) }

  let(:acceptor_tags)  { double('acceptor_tags') }
  let(:acceptor_media) { double('acceptor_media') }

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

  it 'shows the contact for an acceptor' do
    expect(Flapjack::Data::Acceptor).to receive(:lock).
      with(Flapjack::Data::Contact).
      and_yield

    expect(acceptor).to receive(:contact).and_return(contact)

    acceptors = double('acceptor', :all => [acceptor])
    expect(acceptors).to receive(:empty?).and_return(false)
    expect(Flapjack::Data::Acceptor).to receive(:intersect).
      with(:id => acceptor.id).and_return(acceptors)

    get "/acceptors/#{acceptor.id}/contact"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => {:type => 'contact', :id => contact.id},
      :links => {
        :self    => "http://example.org/acceptors/#{acceptor.id}/relationships/contact",
        :related => "http://example.org/acceptors/#{acceptor.id}/contact",
      }
    ))
  end

  it 'cannot change the contact for an acceptor' do
    patch "/acceptors/#{acceptor.id}/relationships/contact", Flapjack.dump_json(:data => {
      :type => 'contact', :id => contact.id
    }), jsonapi_env
    expect(last_response.status).to eq(404)
  end

  it 'adds a medium to a acceptor' do
    expect(Flapjack::Data::Acceptor).to receive(:lock).
      with(Flapjack::Data::Medium).
      and_yield

    expect(Flapjack::Data::Acceptor).to receive(:find_by_id!).with(acceptor.id).
      and_return(acceptor)

    expect(acceptor_media).to receive(:add_ids).with(medium.id)
    expect(acceptor).to receive(:media).and_return(acceptor_media)

    post "/acceptors/#{acceptor.id}/relationships/media", Flapjack.dump_json(:data => [{
      :type => 'medium', :id => medium.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'lists media for an acceptor' do
    expect(Flapjack::Data::Acceptor).to receive(:lock).
      with(Flapjack::Data::Medium).
      and_yield

    sorted = double('sorted')
    paged  = double('paged')
    expect(paged).to receive(:ids).and_return([medium.id])
    expect(sorted).to receive(:page).with(1, :per_page => 20).and_return(paged)
    expect(sorted).to receive(:count).and_return(1)
    expect(acceptor_media).to receive(:sort).with(:id => :asc).and_return(sorted)
    expect(acceptor).to receive(:media).and_return(acceptor_media)

    acceptors = double('acceptor', :all => [acceptor])
    expect(acceptors).to receive(:empty?).and_return(false)
    expect(Flapjack::Data::Acceptor).to receive(:intersect).
      with(:id => acceptor.id).and_return(acceptors)

    get "/acceptors/#{acceptor.id}/media"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => [{:type => 'medium', :id => medium.id}],
      :links => {
        :self    => "http://example.org/acceptors/#{acceptor.id}/relationships/media",
        :related => "http://example.org/acceptors/#{acceptor.id}/media",
      },
      :meta => meta
    ))
  end

  it 'updates media for an acceptor' do
    expect(Flapjack::Data::Acceptor).to receive(:lock).
      with(Flapjack::Data::Medium).
      and_yield

    expect(Flapjack::Data::Acceptor).to receive(:find_by_id!).with(acceptor.id).
      and_return(acceptor)

    expect(acceptor_media).to receive(:ids).and_return([])
    expect(acceptor_media).to receive(:add_ids).with(medium.id)
    expect(acceptor).to receive(:media).twice.and_return(acceptor_media)

    patch "/acceptors/#{acceptor.id}/relationships/media", Flapjack.dump_json(:data => [{
      :type => 'medium', :id => medium.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'deletes a medium from an acceptor' do
    expect(Flapjack::Data::Acceptor).to receive(:lock).
      with(Flapjack::Data::Medium).
      and_yield

    expect(Flapjack::Data::Acceptor).to receive(:find_by_id!).with(acceptor.id).
      and_return(acceptor)

    expect(acceptor_media).to receive(:remove_ids).with(medium.id)
    expect(acceptor).to receive(:media).and_return(acceptor_media)

    delete "/acceptors/#{acceptor.id}/relationships/media", Flapjack.dump_json(:data => [{
      :type => 'medium', :id => medium.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'adds tags to an acceptor' do
    expect(Flapjack::Data::Acceptor).to receive(:lock).
      with(Flapjack::Data::Tag).
      and_yield

    expect(Flapjack::Data::Acceptor).to receive(:find_by_id!).with(acceptor.id).
      and_return(acceptor)

    expect(acceptor_tags).to receive(:add_ids).with(tag.id)
    expect(acceptor).to receive(:tags).and_return(acceptor_tags)

    post "/acceptors/#{acceptor.id}/relationships/tags", Flapjack.dump_json(:data => [{
      :type => 'tag', :id => tag.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'lists tags for an acceptor' do
    expect(Flapjack::Data::Acceptor).to receive(:lock).
      with(Flapjack::Data::Tag).
      and_yield

    sorted = double('sorted')
    paged  = double('paged')
    expect(paged).to receive(:ids).and_return([tag.id])
    expect(sorted).to receive(:page).with(1, :per_page => 20).and_return(paged)
    expect(sorted).to receive(:count).and_return(1)
    expect(acceptor_tags).to receive(:sort).with(:id => :asc).and_return(sorted)
    expect(acceptor).to receive(:tags).and_return(acceptor_tags)

    acceptors = double('acceptor', :all => [acceptor])
    expect(acceptors).to receive(:empty?).and_return(false)
    expect(Flapjack::Data::Acceptor).to receive(:intersect).
      with(:id => acceptor.id).and_return(acceptors)

    get "/acceptors/#{acceptor.id}/tags"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => [{:type => 'tag', :id => tag.id}],
      :links => {
        :self    => "http://example.org/acceptors/#{acceptor.id}/relationships/tags",
        :related => "http://example.org/acceptors/#{acceptor.id}/tags",
      },
      :meta => meta
    ))
  end

  it 'updates tags for an acceptor' do
    expect(Flapjack::Data::Acceptor).to receive(:lock).
      with(Flapjack::Data::Tag).
      and_yield

    expect(Flapjack::Data::Acceptor).to receive(:find_by_id!).with(acceptor.id).
      and_return(acceptor)

    expect(acceptor_tags).to receive(:ids).and_return([])
    expect(acceptor_tags).to receive(:add_ids).with(tag.id)
    expect(acceptor).to receive(:tags).twice.and_return(acceptor_tags)

    patch "/acceptors/#{acceptor.id}/relationships/tags", Flapjack.dump_json(:data => [{
      :type => 'tag', :id => tag.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'deletes a tag from an acceptor' do
    expect(Flapjack::Data::Acceptor).to receive(:lock).
      with(Flapjack::Data::Tag).
      and_yield

    expect(Flapjack::Data::Acceptor).to receive(:find_by_id!).with(acceptor.id).
      and_return(acceptor)

    expect(acceptor_tags).to receive(:remove_ids).with(tag.id)
    expect(acceptor).to receive(:tags).and_return(acceptor_tags)

    delete "/acceptors/#{acceptor.id}/relationships/tags", Flapjack.dump_json(:data => [{
      :type => 'tag', :id => tag.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

end
