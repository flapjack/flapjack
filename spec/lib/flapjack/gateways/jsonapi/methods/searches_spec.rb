require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::Searches', :sinatra => true, :logger => true do

  before { skip 'broken, fixing' }

  include_context "jsonapi"

  let(:meta) {
    {:pagination => {
      :page        => 1,
      :per_page    => 20,
      :total_pages => 1,
      :total_count => 1
    }}
  }

  it "retrieves paginated checks matching a filter" do
    check_data = {
      'id'          => '5678',
      'name'        => 'www.example.com:SSH',
      'enabled'     => true
    }

    check = double(Flapjack::Data::Check, :id => check_data['id'])

    filtered = double('filtered')
    expect(Flapjack::Data::Check).to receive(:intersect).with(:enabled => false).
      twice.and_return(filtered)

    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).and_return([check])
    expect(filtered).to receive(:count).and_return(1)
    expect(filtered).to receive(:sort).
      with(:name, :order => 'alpha').and_return(sorted)

    expect(Flapjack::Data::Check).to receive(:as_jsonapi).with(check).
      and_return([check_data])

    get '/search/checks', :enabled => 'f'
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:checks => [check_data], :meta => meta))
  end

  it "retrieves paginated contacts matching a filter" do
    contact_data = {
      'id'          => '321',
      'name'        => 'Herbert Smith',
    }

    contact = double(Flapjack::Data::Contact, :id => contact_data['id'])

    filtered = double('filtered')
    expect(Flapjack::Data::Contact).to receive(:intersect).with(:name => /Herbert/).
      twice.and_return(filtered)

    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).and_return([contact])
    expect(filtered).to receive(:count).and_return(1)
    expect(filtered).to receive(:sort).
      with(:name, :order => 'alpha').and_return(sorted)

    expect(Flapjack::Data::Contact).to receive(:as_jsonapi).with(contact).
      and_return([contact_data])

    get '/search/contacts', :name => 'Herbert'
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:contacts => [contact_data], :meta => meta))
  end

  it "retrieves paginated tags matching a filter" do
    tag_data = {
      'id'          => '234',
      'name'        => 'database'
    }

    tag = double(Flapjack::Data::Tag, :id => tag_data['id'])

    filtered = double('filtered')
    expect(Flapjack::Data::Tag).to receive(:intersect).with(:name => /database/).
      twice.and_return(filtered)

    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).and_return([tag])
    expect(filtered).to receive(:count).and_return(1)
    expect(filtered).to receive(:sort).
      with(:name, :order => 'alpha').and_return(sorted)

    expect(Flapjack::Data::Tag).to receive(:as_jsonapi).with(tag).
      and_return([tag_data])

    get '/search/tags', :name => 'database'
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:tags => [tag_data], :meta => meta))
  end

end
