require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::TagLinks', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"


  let(:tag)   { double(Flapjack::Data::Tag, :id => tag_data[:id]) }
  let(:check) { double(Flapjack::Data::Check, :id => check_data[:id]) }
  let(:rule)  { double(Flapjack::Data::Rule, :id => rule_data[:id]) }

  let(:tag_checks)  { double('tag_checks') }
  let(:tag_rules)  { double('tag_rules') }

  it 'adds a check to a tag' do
    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)
    expect(Flapjack::Data::Check).to receive(:find_by_ids!).with(check.id).
      and_return([check])

    expect(tag_checks).to receive(:add).with(check)
    expect(tag).to receive(:checks).and_return(tag_checks)

    post "/tags/#{tag.id}/links/checks", Flapjack.dump_json(:checks => check.id), jsonapi_post_env
    expect(last_response.status).to eq(204)
  end

  it 'lists checks for a tag' do
    expect(tag_checks).to receive(:ids).and_return([check.id])
    expect(tag).to receive(:checks).and_return(tag_checks)

    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)

    get "/tags/#{tag.id}/links/checks"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to eq(Flapjack.dump_json(:checks => [check.id]))
  end

  it 'updates checks for a tag' do
    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)
    expect(Flapjack::Data::Check).to receive(:find_by_ids!).with(check.id).
      and_return([check])

    expect(tag_checks).to receive(:ids).and_return([])
    expect(tag_checks).to receive(:add).with(check)
    expect(tag).to receive(:checks).twice.and_return(tag_checks)

    put "/tags/#{tag.id}/links/checks", Flapjack.dump_json(:checks => [check.id]), jsonapi_put_env
    expect(last_response.status).to eq(204)
  end

  it 'deletes a check from a tag' do
    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)

    expect(tag_checks).to receive(:find_by_ids!).with(check.id).
      and_return([check])
    expect(tag_checks).to receive(:delete).with(check)
    expect(tag).to receive(:checks).and_return(tag_checks)

    delete "/tags/#{tag.id}/links/checks/#{check.id}"
    expect(last_response.status).to eq(204)
  end

  it 'adds a rule to a tag' do
    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)
    expect(Flapjack::Data::Rule).to receive(:find_by_ids!).with(rule.id).
      and_return([rule])

    expect(tag_rules).to receive(:add).with(rule)
    expect(tag).to receive(:rules).and_return(tag_rules)

    post "/tags/#{tag.id}/links/rules", Flapjack.dump_json(:rules => rule.id), jsonapi_post_env
    expect(last_response.status).to eq(204)
  end

  it 'lists rules for a tag' do
    expect(tag_rules).to receive(:ids).and_return([rule.id])
    expect(tag).to receive(:rules).and_return(tag_rules)

    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)

    get "/tags/#{tag.id}/links/rules"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to eq(Flapjack.dump_json(:rules => [rule.id]))
  end

  it 'updates rules for a tag' do
    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)
    expect(Flapjack::Data::Rule).to receive(:find_by_ids!).with(rule.id).
      and_return([rule])

    expect(tag_rules).to receive(:ids).and_return([])
    expect(tag_rules).to receive(:add).with(rule)
    expect(tag).to receive(:rules).twice.and_return(tag_rules)

    put "/tags/#{tag.id}/links/rules", Flapjack.dump_json(:rules => [rule.id]), jsonapi_put_env
    expect(last_response.status).to eq(204)
  end

  it 'deletes a rule from a tag' do
    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)

    expect(tag_rules).to receive(:find_by_ids!).with(rule.id).
      and_return([rule])
    expect(tag_rules).to receive(:delete).with(rule)
    expect(tag).to receive(:rules).and_return(tag_rules)

    delete "/tags/#{tag.id}/links/rules/#{rule.id}"
    expect(last_response.status).to eq(204)
  end

end
