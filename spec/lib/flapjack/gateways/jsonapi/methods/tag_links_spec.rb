require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::TagLinks', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:tag)   { double(Flapjack::Data::Tag, :id => tag_data[:name]) }
  let(:check) { double(Flapjack::Data::Check, :id => check_data[:id]) }
  let(:acceptor)  { double(Flapjack::Data::Acceptor, :id => acceptor_data[:id]) }
  let(:rejector)  { double(Flapjack::Data::Rejector, :id => rejector_data[:id]) }

  let(:tag_checks)  { double('tag_checks') }
  let(:tag_acceptors)  { double('tag_acceptors') }
  let(:tag_rejectors)  { double('tag_rejectors') }

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

  it 'adds a check to a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Check).
      and_yield

    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)

    expect(tag_checks).to receive(:add_ids).with(check.id)
    expect(tag).to receive(:checks).and_return(tag_checks)

    post "/tags/#{tag.id}/relationships/checks", Flapjack.dump_json(:data => [{
      :type => 'check', :id => check.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'lists checks for a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Check).
      and_yield

    sorted = double('sorted')
    paged  = double('paged')
    expect(paged).to receive(:ids).and_return([check.id])
    expect(sorted).to receive(:page).with(1, :per_page => 20).and_return(paged)
    expect(sorted).to receive(:count).and_return(1)
    expect(tag_checks).to receive(:sort).with(:id => :asc).and_return(sorted)
    expect(tag).to receive(:checks).and_return(tag_checks)

    tags = double('tags', :all => [tag])
    expect(tags).to receive(:empty?).and_return(false)
    expect(Flapjack::Data::Tag).to receive(:intersect).
      with(:id => tag.id).and_return(tags)

    get "/tags/#{tag.id}/checks"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => [{:type => 'check', :id => check.id}],
      :links => {
        :self    => "http://example.org/tags/#{tag.id}/relationships/checks",
        :related => "http://example.org/tags/#{tag.id}/checks",
      },
      :meta => meta
    ))
  end

  it 'updates checks for a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Check).
      and_yield

    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)

    expect(tag_checks).to receive(:ids).and_return([])
    expect(tag_checks).to receive(:add_ids).with(check.id)
    expect(tag).to receive(:checks).twice.and_return(tag_checks)

    patch "/tags/#{tag.id}/relationships/checks", Flapjack.dump_json(:data => [{
      :type => 'check', :id => check.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'deletes a check from a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Check).
      and_yield

    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)

    expect(tag_checks).to receive(:remove_ids).with(check.id)
    expect(tag).to receive(:checks).and_return(tag_checks)

    delete "/tags/#{tag.id}/relationships/checks", Flapjack.dump_json(:data => [{
      :type => 'check', :id => check.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'adds an acceptor to a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Acceptor).
      and_yield

    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)

    expect(tag_acceptors).to receive(:add_ids).with(acceptor.id)
    expect(tag).to receive(:acceptors).and_return(tag_acceptors)

    post "/tags/#{tag.id}/relationships/acceptors", Flapjack.dump_json(:data => [{
      :type => 'acceptor', :id => acceptor.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'lists acceptors for a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Acceptor).
      and_yield

    sorted = double('sorted')
    paged  = double('paged')
    expect(paged).to receive(:ids).and_return([acceptor.id])
    expect(sorted).to receive(:page).with(1, :per_page => 20).and_return(paged)
    expect(sorted).to receive(:count).and_return(1)
    expect(tag_acceptors).to receive(:sort).with(:id => :asc).and_return(sorted)
    expect(tag).to receive(:acceptors).and_return(tag_acceptors)

    tags = double('tags', :all => [tag])
    expect(tags).to receive(:empty?).and_return(false)
    expect(Flapjack::Data::Tag).to receive(:intersect).
      with(:id => tag.id).and_return(tags)

    get "/tags/#{tag.id}/acceptors"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => [{:type => 'acceptor', :id => acceptor.id}],
      :links => {
        :self    => "http://example.org/tags/#{tag.id}/relationships/acceptors",
        :related => "http://example.org/tags/#{tag.id}/acceptors",
      },
      :meta => meta
    ))
  end

  it 'updates acceptors for a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Acceptor).
      and_yield

    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)

    expect(tag_acceptors).to receive(:ids).and_return([])
    expect(tag_acceptors).to receive(:add_ids).with(acceptor.id)
    expect(tag).to receive(:acceptors).twice.and_return(tag_acceptors)

    patch "/tags/#{tag.id}/relationships/acceptors", Flapjack.dump_json(:data => [{
      :type => 'acceptor', :id => acceptor.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'deletes an acceptor from a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Acceptor).
      and_yield

    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)

    expect(tag_acceptors).to receive(:remove_ids).with(acceptor.id)
    expect(tag).to receive(:acceptors).and_return(tag_acceptors)

    delete "/tags/#{tag.id}/relationships/acceptors", Flapjack.dump_json(:data => [{
      :type => 'acceptor', :id => acceptor.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'adds a rejector to a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Rejector).
      and_yield

    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)

    expect(tag_rejectors).to receive(:add_ids).with(rejector.id)
    expect(tag).to receive(:rejectors).and_return(tag_rejectors)

    post "/tags/#{tag.id}/relationships/rejectors", Flapjack.dump_json(:data => [{
      :type => 'rejector', :id => rejector.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'lists rejectors for a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Rejector).
      and_yield

    sorted = double('sorted')
    paged  = double('paged')
    expect(paged).to receive(:ids).and_return([rejector.id])
    expect(sorted).to receive(:page).with(1, :per_page => 20).and_return(paged)
    expect(sorted).to receive(:count).and_return(1)
    expect(tag_rejectors).to receive(:sort).with(:id => :asc).and_return(sorted)
    expect(tag).to receive(:rejectors).and_return(tag_rejectors)

    tags = double('tags', :all => [tag])
    expect(tags).to receive(:empty?).and_return(false)
    expect(Flapjack::Data::Tag).to receive(:intersect).
      with(:id => tag.id).and_return(tags)

    get "/tags/#{tag.id}/rejectors"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => [{:type => 'rejector', :id => rejector.id}],
      :links => {
        :self    => "http://example.org/tags/#{tag.id}/relationships/rejectors",
        :related => "http://example.org/tags/#{tag.id}/rejectors",
      },
      :meta => meta
    ))
  end

  it 'updates rejectors for a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Rejector).
      and_yield

    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)

    expect(tag_rejectors).to receive(:ids).and_return([])
    expect(tag_rejectors).to receive(:add_ids).with(rejector.id)
    expect(tag).to receive(:rejectors).twice.and_return(tag_rejectors)

    patch "/tags/#{tag.id}/relationships/rejectors", Flapjack.dump_json(:data => [{
      :type => 'rejector', :id => rejector.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'deletes a rejector from a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Rejector).
      and_yield

    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)

    expect(tag_rejectors).to receive(:remove_ids).with(rejector.id)
    expect(tag).to receive(:rejectors).and_return(tag_rejectors)

    delete "/tags/#{tag.id}/relationships/rejectors", Flapjack.dump_json(:data => [{
      :type => 'rejector', :id => rejector.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

end
