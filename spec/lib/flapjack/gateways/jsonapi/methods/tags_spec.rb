require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::Tags', :sinatra => true, :logger => true, :pact_fixture => true do

  before { skip 'broken, fixing' }

  include_context "jsonapi"

  let(:tag)    { double(Flapjack::Data::Tag, :id =>tag_data[:id],
                          :name => tag_data[:name]) }

  it "creates a tag" do
    expect(Flapjack::Data::Tag).to receive(:lock).with(no_args).and_yield

    tags = double('tags')
    expect(tags).to receive(:map).and_return([])
    expect(Flapjack::Data::Tag).to receive(:intersect).with(:id => [tag_data[:id]]).
      and_return(tags)

    expect(tag).to receive(:invalid?).and_return(false)
    expect(tag).to receive(:save).and_return(true)
    expect(Flapjack::Data::Tag).to receive(:new).
      with(:id => tag_data[:id], :name => tag_data[:name]).and_return(tag)

    expect(Flapjack::Data::Tag).to receive(:as_jsonapi).with(true, tag).and_return(tag_data)

    post "/tags", Flapjack.dump_json(:tags => [tag_data]), jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json(:tags => tag_data))
  end

  it "retrieves paginated tags" do
    meta = {:pagination => {
      :page        => 1,
      :per_page    => 20,
      :total_pages => 1,
      :total_count => 1
    }}

    expect(Flapjack::Data::Tag).to receive(:count).and_return(1)

    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).
      and_return([tag])
    expect(Flapjack::Data::Tag).to receive(:sort).
      with(:name, :order => 'alpha').and_return(sorted)

    expect(tag).to receive(:as_json).and_return(tag_data)

    tag_ids = double('tag_ids')
    expect(tag_ids).to receive(:associated_ids_for).with(:checks).
      and_return({})
    expect(tag_ids).to receive(:associated_ids_for).with(:rules).
      and_return({})
    expect(Flapjack::Data::Tag).to receive(:intersect).with(:id => [tag.id]).
      exactly(2).times.and_return(tag_ids)

    get '/tags'
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:tags => [tag_data], :meta => meta))
  end

  it "retrieves one tag" do
    expect(tag).to receive(:as_json).and_return(tag_data)
    all_tags = double('all_tags', :all => [tag])
    expect(Flapjack::Data::Tag).to receive(:intersect).with(:id => [tag.id]).
      and_return(all_tags)

    tag_ids = double('tag_ids')
    expect(tag_ids).to receive(:associated_ids_for).with(:checks).
      and_return({})
    expect(tag_ids).to receive(:associated_ids_for).with(:rules).
      and_return({})
    expect(Flapjack::Data::Tag).to receive(:intersect).with(:id => [tag.id]).
      exactly(2).times.and_return(tag_ids)

    get "/tags/#{tag.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:tags => [tag_data]))
  end

  it "retrieves several tags" do
    tag_2 = double(Flapjack::Data::Tag, :id => tag_data_2['id'], :name => tag_data_2['name'])

    expect(tag).to receive(:as_json).and_return(tag_data)
    expect(tag_2).to receive(:as_json).and_return(tag_data_2)

    all_tags = double('all_tags', :all => [tag, tag_2])
    expect(Flapjack::Data::Tag).to receive(:intersect).with(:name => [tag.name, tag_2.name]).
      and_return(all_tags)

    tag_ids = double('tag_ids')
    expect(tag_ids).to receive(:associated_ids_for).with(:checks).
      and_return({})
    expect(tag_ids).to receive(:associated_ids_for).with(:rules).
      and_return({})
    expect(Flapjack::Data::Tag).to receive(:intersect).with(:id => [tag.id, tag_2.id]).
      exactly(2).times.and_return(tag_ids)

    get "/tags/#{tag.name},#{tag_2.name}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:tags => [tag_data, tag_data_2]))
  end

  it 'adds a linked check to a tag'

  it 'removes a linked notification rule from a tag'

  it "deletes a tag"

end
