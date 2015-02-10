require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::Tags', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:tag)   { double(Flapjack::Data::Tag, :id => tag_data[:name]) }
  let(:tag_2) { double(Flapjack::Data::Tag, :id => tag_2_data[:name]) }

  let(:tag_data_with_id)   { tag_data.merge(:id => tag_data[:name]) }
  let(:tag_2_data_with_id) { tag_2_data.merge(:id => tag_2_data[:name]) }

  let(:check) { double(Flapjack::Data::Check, :id => check_data[:id]) }
  let(:rule)  { double(Flapjack::Data::Rule, :id => rule_data[:id]) }

  it "creates a tag" do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Check, Flapjack::Data::Rule, Flapjack::Data::Route).
      and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Tag).to receive(:intersect).
      with(:name => [tag_data[:name]]).and_return(empty_ids)

    full_ids = double('full_ids')
    expect(full_ids).to receive(:associated_ids_for).with(:checks).and_return({tag.id => []})
    expect(full_ids).to receive(:associated_ids_for).with(:rules).and_return({tag.id => []})
    expect(Flapjack::Data::Tag).to receive(:intersect).
      with(:id => [tag.id]).twice.and_return(full_ids)

    expect(tag).to receive(:invalid?).and_return(false)
    expect(tag).to receive(:save).and_return(true)
    expect(Flapjack::Data::Tag).to receive(:new).with(tag_data_with_id).
      and_return(tag)

    expect(tag).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(tag_data_with_id)

    post "/tags", Flapjack.dump_json(:tags => tag_data), jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json(:tags => tag_data_with_id.merge(:links => {
      :checks => [],
      :rules => []
    })))
  end

  it 'creates a tag linked to a check' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Check, Flapjack::Data::Rule, Flapjack::Data::Route).
      and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Tag).to receive(:intersect).
      with(:name => [tag_data[:name]]).and_return(empty_ids)

    full_ids = double('full_ids')
    expect(full_ids).to receive(:associated_ids_for).with(:checks).and_return({tag.id => [check.id]})
    expect(full_ids).to receive(:associated_ids_for).with(:rules).and_return({tag.id => []})
    expect(Flapjack::Data::Tag).to receive(:intersect).
      with(:id => [tag.id]).twice.and_return(full_ids)

    expect(Flapjack::Data::Check).to receive(:find_by_ids!).with(check.id).
      and_return([check])

    expect(tag).to receive(:invalid?).and_return(false)
    expect(tag).to receive(:save).and_return(true)
    tag_checks = double('tag_checks')
    expect(tag_checks).to receive(:add).with(check)
    expect(tag).to receive(:checks).and_return(tag_checks)
    expect(Flapjack::Data::Tag).to receive(:new).with(tag_data_with_id).
      and_return(tag)

    expect(tag).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(tag_data_with_id)

    post "/tags", Flapjack.dump_json(:tags => tag_data.merge(:links => {:checks => [check.id]})), jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json(:links => {
        'tags.checks' => 'http://example.org/checks/{tags.checks}',
      },
      :tags => tag_data_with_id.merge(:links => {
      :checks => [check.id],
      :rules => []
    })))
  end

  it 'creates a tag linked to a check and a rule' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Check, Flapjack::Data::Rule, Flapjack::Data::Route).
      and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Tag).to receive(:intersect).
      with(:name => [tag_data[:name]]).and_return(empty_ids)

    full_ids = double('full_ids')
    expect(full_ids).to receive(:associated_ids_for).with(:checks).and_return({tag.id => [check.id]})
    expect(full_ids).to receive(:associated_ids_for).with(:rules).and_return({tag.id => [rule.id]})
    expect(Flapjack::Data::Tag).to receive(:intersect).
      with(:id => [tag.id]).twice.and_return(full_ids)

    expect(Flapjack::Data::Check).to receive(:find_by_ids!).with(check.id).
      and_return([check])

    expect(Flapjack::Data::Rule).to receive(:find_by_ids!).with(rule.id).
      and_return([rule])

    expect(tag).to receive(:invalid?).and_return(false)
    expect(tag).to receive(:save).and_return(true)
    tag_checks = double('tag_checks')
    expect(tag_checks).to receive(:add).with(check)
    expect(tag).to receive(:checks).and_return(tag_checks)
    tag_rules = double('tag_rules')
    expect(tag_rules).to receive(:add).with(rule)
    expect(tag).to receive(:rules).and_return(tag_rules)
    expect(Flapjack::Data::Tag).to receive(:new).with(tag_data_with_id).
      and_return(tag)

    expect(tag).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(tag_data_with_id)

    post "/tags", Flapjack.dump_json(:tags => tag_data.merge(:links => {:checks => [check.id], :rules => [rule.id]})), jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json(:links => {
        'tags.checks' => 'http://example.org/checks/{tags.checks}',
        'tags.rules' => 'http://example.org/rules/{tags.rules}',
      },
      :tags => tag_data_with_id.merge(:links => {
      :checks => [check.id],
      :rules => [rule.id]
    })))
  end

  it "retrieves paginated tags" do
    meta = {
      :pagination => {
        :page        => 1,
        :per_page    => 20,
        :total_pages => 1,
        :total_count => 1
      }
    }

    expect(Flapjack::Data::Tag).to receive(:count).and_return(1)

    page = double('page', :all => [tag])
    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).
      and_return(page)
    expect(Flapjack::Data::Tag).to receive(:sort).with(:name).and_return(sorted)

    full_ids = double('full_ids')
    expect(full_ids).to receive(:associated_ids_for).with(:checks).and_return({tag.id => []})
    expect(full_ids).to receive(:associated_ids_for).with(:rules).and_return({tag.id => []})
    expect(Flapjack::Data::Tag).to receive(:intersect).
      with(:id => [tag.id]).twice.and_return(full_ids)

    expect(tag).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(tag_data)

    get '/tags'
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:tags => [tag_data.merge(:links => {
      :checks => [],
      :rules => []
    })], :meta => meta))
  end

  it "retrieves one tag" do
    expect(Flapjack::Data::Tag).to receive(:find_by_id!).
      with(tag.id).and_return(tag)

    full_ids = double('full_ids')
    expect(full_ids).to receive(:associated_ids_for).with(:checks).and_return({tag.id => []})
    expect(full_ids).to receive(:associated_ids_for).with(:rules).and_return({tag.id => []})
    expect(Flapjack::Data::Tag).to receive(:intersect).
      with(:id => [tag.id]).twice.and_return(full_ids)

    expect(tag).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(tag_data)

    get "/tags/#{tag.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:tags => tag_data.merge(:links => {
      :checks => [],
      :rules => []
    })))
  end

  it "retrieves several tags" do
    sorted = double('sorted')
    expect(sorted).to receive(:find_by_ids!).
      with(tag.id, tag_2.id).and_return([tag, tag_2])
    expect(Flapjack::Data::Tag).to receive(:sort).with(:name).and_return(sorted)

    full_ids = double('full_ids')
    expect(full_ids).to receive(:associated_ids_for).with(:checks).and_return({tag.id => [], tag_2.id => []})
    expect(full_ids).to receive(:associated_ids_for).with(:rules).and_return({tag.id => [], tag_2.id => []})
    expect(Flapjack::Data::Tag).to receive(:intersect).
      with(:id => [tag.id, tag_2.id]).twice.and_return(full_ids)

    expect(tag).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(tag_data)

    expect(tag_2).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(tag_2_data)

    get "/tags/#{tag.id},#{tag_2.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:tags => [
      tag_data.merge(:links => {:checks => [], :rules => []}),
      tag_2_data.merge(:links => {:checks => [], :rules => []})
    ]))
  end

  it 'adds a linked check to a tag' do
    expect(Flapjack::Data::Tag).to receive(:find_by_ids!).
      with(tag.id).and_return([tag])

    expect(Flapjack::Data::Check).to receive(:find_by_ids!).with(check.id).
      and_return([check])

    expect(tag).to receive(:invalid?).and_return(false)
    expect(tag).to receive(:save).and_return(true)
    tag_checks = double('tag_checks')
    expect(tag_checks).to receive(:ids).and_return([])
    expect(tag_checks).to receive(:add).with(check)
    expect(tag).to receive(:checks).twice.and_return(tag_checks)

    put "/tags/#{tag.id}",
      Flapjack.dump_json(:tags =>
        {:id => tag.id, :links => {:checks => [check.id]}}
      ),
      jsonapi_put_env
    expect(last_response.status).to eq(204)
  end

  it 'removes a linked rule from a tag' do
    expect(Flapjack::Data::Tag).to receive(:find_by_ids!).
      with(tag.id).and_return([tag])

    expect(Flapjack::Data::Rule).to receive(:find_by_ids!).with(rule.id).
      and_return([rule])

    expect(tag).to receive(:invalid?).and_return(false)
    expect(tag).to receive(:save).and_return(true)
    tag_rules = double('tag_rules')
    expect(tag_rules).to receive(:ids).and_return([rule.id])
    expect(tag_rules).to receive(:delete).with(rule)
    expect(tag).to receive(:rules).twice.and_return(tag_rules)

    put "/tags/#{tag.id}",
      Flapjack.dump_json(:tags =>
        {:id => tag.id, :links => {:rules => []}}
      ),
      jsonapi_put_env
    expect(last_response.status).to eq(204)
  end

  it 'adds links to checks and rules to two tags'

  it "deletes a tag" do
    tags = double('tags')
    expect(tags).to receive(:ids).and_return([tag.id])
    expect(tags).to receive(:destroy_all)
    expect(Flapjack::Data::Tag).to receive(:intersect).
      with(:id => [tag.id]).and_return(tags)

    delete "/tags/#{tag.id}"
    expect(last_response.status).to eq(204)
  end

  it "deletes multiple tags" do
    tags = double('tags')
    expect(tags).to receive(:ids).
      and_return([tag.id, tag_2.id])
    expect(tags).to receive(:destroy_all)
    expect(Flapjack::Data::Tag).to receive(:intersect).
      with(:id => [tag.id, tag_2.id]).
      and_return(tags)

    delete "/tags/#{tag.id},#{tag_2.id}"
    expect(last_response.status).to eq(204)
  end

  it "does not delete a tag that does not exist" do
    tags = double('tags')
    expect(tags).to receive(:ids).and_return([])
    expect(tags).not_to receive(:destroy_all)
    expect(Flapjack::Data::Tag).to receive(:intersect).
      with(:id => [tag.id]).and_return(tags)

    delete "/tags/#{tag.id}"
    expect(last_response).to be_not_found
  end

end
