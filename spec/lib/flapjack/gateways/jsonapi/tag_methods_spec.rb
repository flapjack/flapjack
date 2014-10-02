require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::TagMethods', :sinatra => true, :logger => true do

  include_context "jsonapi"

  let(:tag_data)   {
    {'id'          => 'abcd',
     'name'        => 'database'
    }
   }

  let(:tag)    { double(Flapjack::Data::Tag, :id =>tag_data['id'], :name => tag_data['name']) }

  it "creates a tag" do
    expect(Flapjack::Data::Tag).to receive(:lock).with(no_args).and_yield

    named = double('named')
    expect(named).to receive(:map).and_return([])
    expect(Flapjack::Data::Tag).to receive(:intersect).with(:name => [tag_data['name']]).
      and_return(named)

    expect(tag).to receive(:invalid?).and_return(false)
    expect(tag).to receive(:save).and_return(true)
    expect(Flapjack::Data::Tag).to receive(:new).
      with(:id => tag_data['id'], :name => tag_data['name']).and_return(tag)

    post "/tags", Flapjack.dump_json(:tags => [tag_data]), jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json([tag_data['name']]))
  end

  it "retrieves all tags" do
    expect(tag).to receive(:as_json).and_return(tag_data)
    expect(Flapjack::Data::Tag).to receive(:all).and_return([tag])

    expect(Flapjack::Data::Tag).to receive(:associated_ids_for_checks).
      with(tag.id).and_return({})
    expect(Flapjack::Data::Tag).to receive(:associated_ids_for_notification_rules).
      with(tag.id).and_return({})

    get '/tags'
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:tags => [tag_data]))
  end

  it "retrieves one tag" do
    expect(tag).to receive(:as_json).and_return(tag_data)
    all_tags = double('all_tags', :all => [tag])
    expect(Flapjack::Data::Tag).to receive(:intersect).with(:name => [tag.name]).
      and_return(all_tags)

    expect(Flapjack::Data::Tag).to receive(:associated_ids_for_checks).
      with(tag.id).and_return({})
    expect(Flapjack::Data::Tag).to receive(:associated_ids_for_notification_rules).
      with(tag.id).and_return({})

    get "/tags/#{tag.name}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:tags => [tag_data]))
  end

  it "retrieves several tags" do
    tag_data_2 = {'name' => 'web', 'id' => 'efgh'}
    tag_2 = double(Flapjack::Data::Tag, :id => tag_data_2['id'], :name => tag_data_2['name'])

    expect(tag).to receive(:as_json).and_return(tag_data)
    expect(tag_2).to receive(:as_json).and_return(tag_data_2)

    all_tags = double('all_tags', :all => [tag, tag_2])
    expect(Flapjack::Data::Tag).to receive(:intersect).with(:name => [tag.name, tag_2.name]).
      and_return(all_tags)

    expect(Flapjack::Data::Tag).to receive(:associated_ids_for_checks).
      with(tag.id, tag_2.id).and_return({})
    expect(Flapjack::Data::Tag).to receive(:associated_ids_for_notification_rules).
      with(tag.id, tag_2.id).and_return({})

    get "/tags/#{tag.name},#{tag_2.name}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:tags => [tag_data, tag_data_2]))
  end

  it 'adds a linked check to a tag'

  it 'removes a linked notification rule from a tag'

  it "deletes a tag"

end
