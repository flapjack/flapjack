require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::CheckLinks', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:check) { double(Flapjack::Data::Check, :id => check_data[:id]) }
  let(:tag)   { double(Flapjack::Data::Tag, :id => tag_data[:name]) }

  let(:check_tags)  { double('check_tags') }

  it 'adds tags to a check' do
    expect(Flapjack::Data::Check).to receive(:lock).
      with(Flapjack::Data::Tag, Flapjack::Data::Rule,
           Flapjack::Data::Route ).and_yield

    expect(Flapjack::Data::Check).to receive(:find_by_id!).with(check.id).
      and_return(check)
    expect(Flapjack::Data::Tag).to receive(:find_by_ids!).with(tag.id).
      and_return([tag])

    expect(check_tags).to receive(:add).with(tag)
    expect(check).to receive(:tags).and_return(check_tags)

    post "/checks/#{check.id}/links/tags", Flapjack.dump_json(:data => [{
      :type => 'tag', :id => tag.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'lists tags for a check' do
    expect(Flapjack::Data::Check).to receive(:lock).
      with(Flapjack::Data::Tag, Flapjack::Data::Rule,
           Flapjack::Data::Route).and_yield

    expect(check_tags).to receive(:ids).and_return([tag.id])
    expect(check).to receive(:tags).and_return(check_tags)

    expect(Flapjack::Data::Check).to receive(:find_by_id!).with(check.id).
      and_return(check)

    get "/checks/#{check.id}/tags"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => [{:type => 'tag', :id => tag.id}],
      :links => {
        :self    => "http://example.org/checks/#{check.id}/links/tags",
        :related => "http://example.org/checks/#{check.id}/tags",
      }
    ))
  end

  it 'updates tags for a check' do
    expect(Flapjack::Data::Check).to receive(:lock).
      with(Flapjack::Data::Tag, Flapjack::Data::Rule,
           Flapjack::Data::Route).and_yield

    expect(Flapjack::Data::Check).to receive(:find_by_id!).with(check.id).
      and_return(check)
    expect(Flapjack::Data::Tag).to receive(:find_by_ids!).with(tag.id).
      and_return([tag])

    expect(check_tags).to receive(:ids).and_return([])
    expect(check_tags).to receive(:add).with(tag)
    expect(check).to receive(:tags).twice.and_return(check_tags)

    patch "/checks/#{check.id}/links/tags", Flapjack.dump_json(:data => [{
      :type => 'tag', :id => tag.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'deletes a tag from a check' do
    expect(Flapjack::Data::Check).to receive(:lock).
      with(Flapjack::Data::Tag, Flapjack::Data::Rule,
           Flapjack::Data::Route).and_yield

    expect(Flapjack::Data::Check).to receive(:find_by_id!).with(check.id).
      and_return(check)

    expect(check_tags).to receive(:find_by_ids!).with(tag.id).
      and_return([tag])
    expect(check_tags).to receive(:delete).with(tag)
    expect(check).to receive(:tags).and_return(check_tags)

    delete "/checks/#{check.id}/links/tags", Flapjack.dump_json(:data => [{
      :type => 'tag', :id => tag.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'adds a scheduled maintenance period to a check'

  it 'lists scheduled maintenance periods for a check'

  it 'updates scheduled maintenance periods for a check'

  it 'deletes a scheduled maintenance period from a check'

  it 'adds an unscheduled maintenance period to a check'

  it 'lists unscheduled maintenance periods for a check'

  it 'updates unscheduled maintenance periods for a check'

  it 'deletes an unscheduled maintenance period from a check'

end
