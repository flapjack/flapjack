require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::Tags', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:tag)   { double(Flapjack::Data::Tag, :id => tag_data[:id]) }
  let(:tag_2) { double(Flapjack::Data::Tag, :id => tag_2_data[:id]) }

  let(:check) { double(Flapjack::Data::Check, :id => check_data[:id]) }
  let(:rule)  { double(Flapjack::Data::Rule, :id => rule_data[:id]) }

  it "creates a tag" do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Check, Flapjack::Data::Rule).and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Tag).to receive(:intersect).
      with(:id => [tag_data[:id]]).and_return(empty_ids)

    expect(tag).to receive(:invalid?).and_return(false)
    expect(tag).to receive(:save).and_return(true)
    expect(Flapjack::Data::Tag).to receive(:new).with(tag_data).
      and_return(tag)

    expect(Flapjack::Data::Tag).to receive(:as_jsonapi).with(nil, true, tag).and_return(tag_data)

    post "/tags", Flapjack.dump_json(:tags => tag_data), jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json(:tags => tag_data))
  end

  it 'creates a tag linked to a check' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Check, Flapjack::Data::Rule).and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Tag).to receive(:intersect).
      with(:id => [tag_data[:id]]).and_return(empty_ids)

    tag_with_check_data = tag_data.merge(:links => {
      :checks => [check.id]
    })

    expect(Flapjack::Data::Check).to receive(:find_by_ids!).with(check.id).
      and_return([check])

    expect(tag).to receive(:invalid?).and_return(false)
    expect(tag).to receive(:save).and_return(true)
    tag_checks = double('tag_checks')
    expect(tag_checks).to receive(:add).with(check)
    expect(tag).to receive(:checks).and_return(tag_checks)
    expect(Flapjack::Data::Tag).to receive(:new).with(tag_data).
      and_return(tag)

    expect(Flapjack::Data::Tag).to receive(:as_jsonapi).with(nil, true, tag).and_return(tag_with_check_data)

    post "/tags", Flapjack.dump_json(:tags => tag_with_check_data), jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json(:tags => tag_with_check_data))
  end

  it 'creates a tag linked to a check and a rule' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Check, Flapjack::Data::Rule).and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Tag).to receive(:intersect).
      with(:id => [tag_data[:id]]).and_return(empty_ids)

    tag_with_check_and_rule_data = tag_data.merge(:links => {
      :checks => [check.id],
      :rules  => [rule.id],
    })

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
    expect(Flapjack::Data::Tag).to receive(:new).with(tag_data).
      and_return(tag)

    expect(Flapjack::Data::Tag).to receive(:as_jsonapi).with(nil, true, tag).and_return(tag_with_check_and_rule_data)

    post "/tags", Flapjack.dump_json(:tags => tag_with_check_and_rule_data), jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json(:tags => tag_with_check_and_rule_data))
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

    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).
      and_return([tag])
    expect(Flapjack::Data::Tag).to receive(:sort).
      with(:name, :order => 'alpha').and_return(sorted)

    expect(Flapjack::Data::Tag).to receive(:as_jsonapi).with(nil, false, tag).and_return([tag_data])

    get '/tags'
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:tags => [tag_data], :meta => meta))
  end

  it "retrieves one tag" do
    expect(Flapjack::Data::Tag).to receive(:find_by_ids!).
      with(tag.id).and_return([tag])

    expect(Flapjack::Data::Tag).to receive(:as_jsonapi).with(nil, true, tag).and_return(tag_data)

    get "/tags/#{tag.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:tags => tag_data))
  end

  it "retrieves several tags" do
    expect(Flapjack::Data::Tag).to receive(:find_by_ids!).
      with(tag.id, tag_2.id).and_return([tag, tag_2])

    expect(Flapjack::Data::Tag).to receive(:as_jsonapi).with(nil, false, tag, tag_2).and_return([tag_data, tag_2_data])

    get "/tags/#{tag.id},#{tag_2.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:tags => [tag_data, tag_2_data]))
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
