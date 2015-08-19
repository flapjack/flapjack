require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::MediumLinks', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:medium)  { double(Flapjack::Data::Medium, :id => email_data[:id]) }
  let(:contact) { double(Flapjack::Data::Contact, :id => contact_data[:id]) }
  let(:acceptor)    { double(Flapjack::Data::Acceptor, :id => acceptor_data[:id]) }

  let(:medium_acceptors)  { double('medium_acceptors') }

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

  it 'shows the contact for a medium' do
    expect(Flapjack::Data::Medium).to receive(:lock).
      with(Flapjack::Data::Contact).and_yield

    expect(medium).to receive(:contact).and_return(contact)

    media = double('media', :all => [medium])
    expect(media).to receive(:empty?).and_return(false)
    expect(Flapjack::Data::Medium).to receive(:intersect).
      with(:id => medium.id).and_return(media)

    get "/media/#{medium.id}/contact"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => {:type => 'contact', :id => contact.id},
      :links => {
        :self    => "http://example.org/media/#{medium.id}/relationships/contact",
        :related => "http://example.org/media/#{medium.id}/contact",
      }
    ))
  end

  it 'cannot change the contact for a medium' do
    patch "/media/#{medium.id}/relationships/contact", Flapjack.dump_json(
      :data => {
        :type => 'contact',
        :id   => contact.id,
      }
    ), jsonapi_env
    expect(last_response.status).to eq(404)
  end

  it 'cannot clear the contact for a medium' do
    patch "/media/#{medium.id}/relationships/contact", Flapjack.dump_json(
      :data => {
        :type => 'contact',
        :id   => nil,
      }
    ), jsonapi_env
    expect(last_response.status).to eq(404)
  end

  it 'adds a acceptor to a medium' do
    expect(Flapjack::Data::Medium).to receive(:lock).
      with(Flapjack::Data::Acceptor).and_yield

    expect(Flapjack::Data::Medium).to receive(:find_by_id!).with(medium.id).
      and_return(medium)

    expect(medium_acceptors).to receive(:add_ids).with(acceptor.id)
    expect(medium).to receive(:acceptors).and_return(medium_acceptors)

    post "/media/#{medium.id}/relationships/acceptors", Flapjack.dump_json(
      :data => [{:type => 'acceptor', :id => acceptor.id}]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'lists acceptors for a medium' do
    expect(Flapjack::Data::Medium).to receive(:lock).
      with(Flapjack::Data::Acceptor).and_yield

    sorted = double('sorted')
    paged  = double('paged')
    expect(paged).to receive(:ids).and_return([acceptor.id])
    expect(sorted).to receive(:page).with(1, :per_page => 20).and_return(paged)
    expect(sorted).to receive(:count).and_return(1)
    expect(medium_acceptors).to receive(:sort).with(:id => :asc).and_return(sorted)
    expect(medium).to receive(:acceptors).and_return(medium_acceptors)

    media = double('media', :all => [medium])
    expect(media).to receive(:empty?).and_return(false)
    expect(Flapjack::Data::Medium).to receive(:intersect).
      with(:id => medium.id).and_return(media)

    get "/media/#{medium.id}/acceptors"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => [{:type => 'acceptor', :id => acceptor.id}],
      :links => {
        :self    => "http://example.org/media/#{medium.id}/relationships/acceptors",
        :related => "http://example.org/media/#{medium.id}/acceptors",
      },
      :meta => meta
    ))
  end

  it 'updates acceptors for a medium' do
    expect(Flapjack::Data::Medium).to receive(:lock).
      with(Flapjack::Data::Acceptor).and_yield

    expect(Flapjack::Data::Medium).to receive(:find_by_id!).with(medium.id).
      and_return(medium)

    expect(medium_acceptors).to receive(:ids).and_return([])
    expect(medium_acceptors).to receive(:add_ids).with(acceptor.id)
    expect(medium).to receive(:acceptors).twice.and_return(medium_acceptors)

    patch "/media/#{medium.id}/relationships/acceptors", Flapjack.dump_json(
      :data => [
        {:type => 'acceptor', :id => acceptor.id}
      ]
    ), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'clears acceptors for a medium' do
    expect(Flapjack::Data::Medium).to receive(:lock).
      with(Flapjack::Data::Acceptor).and_yield

    expect(Flapjack::Data::Medium).to receive(:find_by_id!).with(medium.id).
      and_return(medium)

    expect(medium_acceptors).to receive(:ids).and_return([acceptor.id])
    expect(medium_acceptors).to receive(:remove_ids).with(acceptor.id)
    expect(medium).to receive(:acceptors).twice.and_return(medium_acceptors)

    patch "/media/#{medium.id}/relationships/acceptors", Flapjack.dump_json(
      :data => []
    ), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'deletes a acceptor from a medium' do
    expect(Flapjack::Data::Medium).to receive(:lock).
      with(Flapjack::Data::Acceptor).and_yield

    expect(Flapjack::Data::Medium).to receive(:find_by_id!).with(medium.id).
      and_return(medium)

    expect(medium_acceptors).to receive(:remove_ids).with(acceptor.id)
    expect(medium).to receive(:acceptors).and_return(medium_acceptors)

    delete "/media/#{medium.id}/relationships/acceptors", Flapjack.dump_json(
      :data => [{:type => 'acceptor', :id => acceptor.id}]
    ), jsonapi_env
    expect(last_response.status).to eq(204)
  end

end
