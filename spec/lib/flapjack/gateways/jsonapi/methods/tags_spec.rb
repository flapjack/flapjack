require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::Tags', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:tag)   { double(Flapjack::Data::Tag, :id => tag_data[:id]) }
  let(:tag_2) { double(Flapjack::Data::Tag, :id => tag_2_data[:id]) }

  let(:tag_data_with_id)   { tag_data.merge(:id => tag_data[:id]) }
  let(:tag_2_data_with_id) { tag_2_data.merge(:id => tag_2_data[:id]) }

  let(:check) { double(Flapjack::Data::Check, :id => check_data[:id]) }

  it "creates a tag" do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(no_args).
      and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Tag).to receive(:intersect).
      with(:id => [tag_data[:id]]).and_return(empty_ids)

    expect(tag).to receive(:invalid?).and_return(false)
    expect(tag).to receive(:save!).and_return(true)
    expect(Flapjack::Data::Tag).to receive(:new).with(tag_data_with_id).
      and_return(tag)

    expect(tag).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(tag_data_with_id)

    req_data  = tag_json(tag_data)
    resp_data = req_data.merge(:relationships => tag_rel(tag_data))

    post "/tags", Flapjack.dump_json(:data => req_data), jsonapi_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data =>
      resp_data))
  end

  it "retrieves paginated tags" do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(no_args).
      and_yield

    meta = {
      :pagination => {
        :page        => 1,
        :per_page    => 20,
        :total_pages => 1,
        :total_count => 1
      }
    }

    links = {
      :self  => 'http://example.org/tags',
      :first => 'http://example.org/tags?page=1',
      :last  => 'http://example.org/tags?page=1'
    }

    page = double('page')
    expect(page).to receive(:empty?).and_return(false)
    expect(page).to receive(:ids).and_return([tag.id])
    expect(page).to receive(:collect) {|&arg| [arg.call(tag)] }
    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).
      and_return(page)
    expect(sorted).to receive(:count).and_return(1)
    expect(Flapjack::Data::Tag).to receive(:sort).with(:id).and_return(sorted)

    expect(tag).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(tag_data)

    resp_data = [tag_json(tag_data).merge(:relationships => tag_rel(tag_data))]

    get '/tags'
    expect(last_response).to be_ok
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data =>
      resp_data, :links => links, :meta => meta))
  end

  it "retrieves paginated tags matching a filter" do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(no_args).
      and_yield

    meta = {
      :pagination => {
        :page        => 1,
        :per_page    => 20,
        :total_pages => 1,
        :total_count => 1
      }
    }

    links = {
      :self  => 'http://example.org/tags?filter%5B%5D=name%3Adatabase',
      :first => 'http://example.org/tags?filter%5B%5D=name%3Adatabase&page=1',
      :last  => 'http://example.org/tags?filter%5B%5D=name%3Adatabase&page=1'
    }

    filtered = double('filtered')
    expect(Flapjack::Data::Tag).to receive(:intersect).with(:name => Regexp.new('database')).
      and_return(filtered)

    page = double('page')
    expect(page).to receive(:empty?).and_return(false)
    expect(page).to receive(:ids).and_return([tag.id])
    expect(page).to receive(:collect) {|&arg| [arg.call(tag)] }
    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).and_return(page)
    expect(sorted).to receive(:count).and_return(1)
    expect(filtered).to receive(:sort).with(:id).and_return(sorted)

    expect(tag).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(tag_data)

    resp_data = [tag_json(tag_data).merge(:relationships => tag_rel(tag_data))]

    get '/tags?filter%5B%5D=name%3Adatabase'
    expect(last_response).to be_ok
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data =>
      resp_data, :links => links, :meta => meta))
  end

  it "retrieves one tag" do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(no_args).
      and_yield

    expect(Flapjack::Data::Tag).to receive(:intersect).
      with(:id => Set.new([tag.id])).and_return([tag])

    expect(tag).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(tag_data)

    resp_data = tag_json(tag_data).merge(:relationships => tag_rel(tag_data))

    get "/tags/#{tag.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data =>
      resp_data, :links => {:self  => "http://example.org/tags/#{tag.id}"}))
  end

  it "retrieves several tags" do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(no_args).
      and_yield

    meta = {
      :pagination => {
        :page        => 1,
        :per_page    => 20,
        :total_pages => 1,
        :total_count => 2
      }
    }

    links = {
      :self  => "http://example.org/tags?filter%5B%5D=id%3A#{tag.id}%7C#{tag_2.id}",
      :first => "http://example.org/tags?filter%5B%5D=id%3A#{tag.id}%7C#{tag_2.id}&page=1",
      :last  => "http://example.org/tags?filter%5B%5D=id%3A#{tag.id}%7C#{tag_2.id}&page=1"
    }

    page = double('page')
    expect(page).to receive(:empty?).and_return(false)
    expect(page).to receive(:ids).and_return([tag.id, tag_2.id])
    expect(page).to receive(:collect) {|&arg| [arg.call(tag), arg.call(tag_2)] }

    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).and_return(page)
    expect(sorted).to receive(:count).and_return(2)

    filtered = double('filtered')
    expect(filtered).to receive(:sort).with(:id).and_return(sorted)
    expect(Flapjack::Data::Tag).to receive(:intersect).with(:id => [tag.id, tag_2.id]).
      and_return(filtered)

    expect(tag).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(tag_data)

    expect(tag_2).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(tag_2_data)

    resp_data = [
      tag_json(tag_data).merge(:relationships => tag_rel(tag_data)),
      tag_json(tag_2_data).merge(:relationships => tag_rel(tag_2_data))
    ]

    get "/tags?filter=id%3A#{tag.id}%7C#{tag_2.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data => resp_data, :links => links, :meta => meta))
  end

  it "updates a tag" do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(no_args).
      and_yield

    expect(Flapjack::Data::Tag).to receive(:find_by_id!).
      with(tag.id).and_return(tag)

    expect(tag).to receive(:name=).with('database_only')
    expect(tag).to receive(:invalid?).and_return(false)
    expect(tag).to receive(:save!).and_return(true)

    patch "/tags/#{tag.id}",
      Flapjack.dump_json(:data => {:id => tag.id,
        :type => 'tag', :attributes => {:name => 'database_only'}}),
      jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'sets a linked check for a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Check).
      and_yield

    expect(Flapjack::Data::Check).to receive(:find_by_ids!).
      with(check.id).and_return([check])

    expect(tag).to receive(:invalid?).and_return(false)
    expect(tag).to receive(:save!).and_return(true)

    checks = double('checks', :ids => [])
    expect(checks).to receive(:add).with(check)
    expect(tag).to receive(:checks).twice.and_return(checks)

    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).and_return(tag)

    patch "/tags/#{tag.id}",
      Flapjack.dump_json(:data => {:id => tag.id, :type => 'tag', :relationships =>
        {:checks => {:data => [{:type => 'check', :id => check.id}]}}}),
      jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it "deletes a tag" do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Check,
           Flapjack::Data::Contact,
           Flapjack::Data::Rule,
           Flapjack::Data::ScheduledMaintenance,
           Flapjack::Data::State,
           Flapjack::Data::UnscheduledMaintenance).
      and_yield

    expect(tag).to receive(:destroy)
    expect(Flapjack::Data::Tag).to receive(:find_by_id!).
      with(tag.id).and_return(tag)

    delete "/tags/#{tag.id}"
    expect(last_response.status).to eq(204)
  end

  it "deletes multiple tags" do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Check,
           Flapjack::Data::Contact,
           Flapjack::Data::Rule,
           Flapjack::Data::ScheduledMaintenance,
           Flapjack::Data::State,
           Flapjack::Data::UnscheduledMaintenance).
      and_yield

    tags = double('tags')
    expect(tags).to receive(:count).and_return(2)
    expect(tags).to receive(:destroy_all)
    expect(Flapjack::Data::Tag).to receive(:intersect).
      with(:id => [tag.id, tag_2.id]).and_return(tags)

    delete "/tags",
      Flapjack.dump_json(:data => [
        {:id => tag.id, :type => 'tag'},
        {:id => tag_2.id, :type => 'tag'}
      ]),
      jsonapi_bulk_env

    expect(last_response.status).to eq(204)
  end

  it "does not delete a tag that does not exist" do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Check,
           Flapjack::Data::Contact,
           Flapjack::Data::Rule,
           Flapjack::Data::ScheduledMaintenance,
           Flapjack::Data::State,
           Flapjack::Data::UnscheduledMaintenance).
      and_yield

    expect(Flapjack::Data::Tag).to receive(:find_by_id!).
      with(tag.id).and_raise(Zermelo::Records::Errors::RecordNotFound.new(Flapjack::Data::Tag, tag.id))

    delete "/tags/#{tag.id}"
    expect(last_response).to be_not_found
  end

end
