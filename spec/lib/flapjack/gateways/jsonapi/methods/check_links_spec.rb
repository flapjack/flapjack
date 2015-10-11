require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::CheckLinks', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:check) { double(Flapjack::Data::Check, :id => check_data[:id]) }
  let(:tag)   { double(Flapjack::Data::Tag, :id => tag_data[:id]) }

  let(:check_tags)  { double('check_tags') }

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

  it 'adds tags to a check' do
    expect(Flapjack::Data::Check).to receive(:lock).
      with(Flapjack::Data::Tag).
      and_yield

    expect(Flapjack::Data::Check).to receive(:find_by_id!).with(check.id).
      and_return(check)

    expect(check_tags).to receive(:add_ids).with(tag.id)
    expect(check).to receive(:tags).and_return(check_tags)

    post "/checks/#{check.id}/relationships/tags", Flapjack.dump_json(:data => [{
      :type => 'tag', :id => tag.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'lists tags for a check' do
    expect(Flapjack::Data::Check).to receive(:lock).
      with(Flapjack::Data::Tag).
      and_yield

    sorted = double('sorted')
    paged  = double('paged')
    expect(paged).to receive(:ids).and_return([tag.id])
    expect(sorted).to receive(:page).with(1, :per_page => 20).and_return(paged)
    expect(sorted).to receive(:count).and_return(1)
    expect(check_tags).to receive(:sort).with(:id => :asc).and_return(sorted)
    expect(check).to receive(:tags).and_return(check_tags)

    checks = double('checks', :all => [check])
    expect(checks).to receive(:empty?).and_return(false)
    expect(Flapjack::Data::Check).to receive(:intersect).
      with(:id => check.id).and_return(checks)

    get "/checks/#{check.id}/tags"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => [{:type => 'tag', :id => tag.id}],
      :links => {
        :self    => "http://example.org/checks/#{check.id}/relationships/tags",
        :related => "http://example.org/checks/#{check.id}/tags",
      },
      :meta => meta
    ))
  end

  it 'lists tags for a check, including tag data' do
    expect(Flapjack::Data::Check).to receive(:lock).
      with(Flapjack::Data::Tag).
      and_yield

    sorted = double('sorted')
    paged  = double('paged')
    expect(paged).to receive(:ids).and_return([tag.id])
    expect(sorted).to receive(:page).with(1, :per_page => 20).and_return(paged)
    expect(sorted).to receive(:count).and_return(1)
    expect(check_tags).to receive(:sort).with(:id => :asc).and_return(sorted)
    expect(check).to receive(:tags).and_return(check_tags)

    full_tags = double('full_tags')
    expect(full_tags).to receive(:collect) {|&arg| [arg.call(tag)] }

    expect(Flapjack::Data::Tag).to receive(:intersect).
      with(:id => [tag.id]).and_return(full_tags)

    expect(tag).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(tag_data.merge(:id => tag.id))

    checks = double('checks', :all => [check])
    expect(checks).to receive(:empty?).and_return(false)
    expect(checks).to receive(:associated_ids_for).with(:tags).
      and_return(check.id => [tag.id])
    expect(checks).to receive(:ids).and_return(Set.new([check.id]))
    expect(Flapjack::Data::Check).to receive(:intersect).
      with(:id => Set.new([check.id])).and_return(checks)
    expect(Flapjack::Data::Check).to receive(:intersect).
      with(:id => check.id).and_return(checks)

    get "/checks/#{check.id}/tags?include=tags"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => [{:type => 'tag', :id => tag.id}],
      :included => [{
        :id => tag.id,
        :type => 'tag',
        :attributes => tag_data.reject {|k,v| :id.eql?(k) }
      }],
      :links => {
        :self    => "http://example.org/checks/#{check.id}/relationships/tags",
        :related => "http://example.org/checks/#{check.id}/tags",
      },
      :meta => meta
    ))
  end

  it 'updates tags for a check' do
    expect(Flapjack::Data::Check).to receive(:lock).
      with(Flapjack::Data::Tag).
      and_yield

    expect(Flapjack::Data::Check).to receive(:find_by_id!).with(check.id).
      and_return(check)

    expect(check_tags).to receive(:ids).and_return([])
    expect(check_tags).to receive(:add_ids).with(tag.id)
    expect(check).to receive(:tags).twice.and_return(check_tags)

    patch "/checks/#{check.id}/relationships/tags", Flapjack.dump_json(:data => [{
      :type => 'tag', :id => tag.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'deletes a tag from a check' do
    expect(Flapjack::Data::Check).to receive(:lock).
      with(Flapjack::Data::Tag).
      and_yield

    expect(Flapjack::Data::Check).to receive(:find_by_id!).with(check.id).
      and_return(check)

    expect(check_tags).to receive(:remove_ids).with(tag.id)
    expect(check).to receive(:tags).and_return(check_tags)

    delete "/checks/#{check.id}/relationships/tags", Flapjack.dump_json(:data => [{
      :type => 'tag', :id => tag.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

end
