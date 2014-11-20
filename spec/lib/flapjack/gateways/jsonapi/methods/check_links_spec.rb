require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::CheckLinks', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:check) { double(Flapjack::Data::Check, :id => check_data[:id]) }
  let(:tag)   { double(Flapjack::Data::Tag, :id => tag_data[:id]) }

  let(:check_tags)  { double('check_tags') }

  it 'adds tags to a check' do
    expect(Flapjack::Data::Check).to receive(:find_by_id!).with(check.id).
      and_return(check)
    expect(Flapjack::Data::Tag).to receive(:find_by_ids!).with(tag.id).
      and_return([tag])

    expect(check_tags).to receive(:add).with(tag)
    expect(check).to receive(:tags).and_return(check_tags)

    post "/checks/#{check.id}/links/tags", Flapjack.dump_json(:tags => tag.id), jsonapi_post_env
    expect(last_response.status).to eq(204)
  end

  it 'lists tags for a check' do
    expect(check_tags).to receive(:ids).and_return([tag.id])
    expect(check).to receive(:tags).and_return(check_tags)

    expect(Flapjack::Data::Check).to receive(:find_by_id!).with(check.id).
      and_return(check)

    get "/checks/#{check.id}/links/tags"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to eq(Flapjack.dump_json(:tags => [tag.id]))
  end

  it 'updates tags for a check' do
    expect(Flapjack::Data::Check).to receive(:find_by_id!).with(check.id).
      and_return(check)
    expect(Flapjack::Data::Tag).to receive(:find_by_ids!).with(tag.id).
      and_return([tag])

    expect(check_tags).to receive(:ids).and_return([])
    expect(check_tags).to receive(:add).with(tag)
    expect(check).to receive(:tags).twice.and_return(check_tags)

    put "/checks/#{check.id}/links/tags", Flapjack.dump_json(:tags => [tag.id]), jsonapi_put_env
    expect(last_response.status).to eq(204)
  end

  it 'deletes a tag from a check' do
    expect(Flapjack::Data::Check).to receive(:find_by_id!).with(check.id).
      and_return(check)

    expect(check_tags).to receive(:find_by_ids!).with(tag.id).
      and_return([tag])
    expect(check_tags).to receive(:delete).with(tag)
    expect(check).to receive(:tags).and_return(check_tags)

    delete "/checks/#{check.id}/links/tags/#{tag.id}"
    expect(last_response.status).to eq(204)
  end

end
