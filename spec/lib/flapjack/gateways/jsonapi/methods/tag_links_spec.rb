require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::TagLinks', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"


  let(:tag)   { double(Flapjack::Data::Tag, :id => tag_data[:name]) }
  let(:check) { double(Flapjack::Data::Check, :id => check_data[:id]) }
  let(:rule)  { double(Flapjack::Data::Rule, :id => rule_data[:id]) }

  let(:tag_checks)  { double('tag_checks') }
  let(:tag_rules)  { double('tag_rules') }

  it 'adds a check to a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Check, Flapjack::Data::Contact, Flapjack::Data::Rule,
           Flapjack::Data::Route).and_yield

    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)

    expect(tag_checks).to receive(:add_ids).with(check.id)
    expect(tag).to receive(:checks).and_return(tag_checks)

    post "/tags/#{tag.id}/links/checks", Flapjack.dump_json(:data => [{
      :type => 'check', :id => check.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'lists checks for a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Check, Flapjack::Data::Contact, Flapjack::Data::Rule,
           Flapjack::Data::Route).and_yield

    expect(tag_checks).to receive(:ids).and_return([check.id])
    expect(tag).to receive(:checks).and_return(tag_checks)

    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)

    get "/tags/#{tag.id}/checks"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => [{:type => 'check', :id => check.id}],
      :links => {
        :self    => "http://example.org/tags/#{tag.id}/links/checks",
        :related => "http://example.org/tags/#{tag.id}/checks",
      }
    ))
  end

  it 'updates checks for a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Check, Flapjack::Data::Contact, Flapjack::Data::Rule,
           Flapjack::Data::Route).and_yield

    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)

    expect(tag_checks).to receive(:ids).and_return([])
    expect(tag_checks).to receive(:add_ids).with(check.id)
    expect(tag).to receive(:checks).twice.and_return(tag_checks)

    patch "/tags/#{tag.id}/links/checks", Flapjack.dump_json(:data => [{
      :type => 'check', :id => check.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'deletes a check from a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Check, Flapjack::Data::Contact, Flapjack::Data::Rule,
           Flapjack::Data::Route).and_yield

    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)

    expect(tag_checks).to receive(:remove_ids).with(check.id)
    expect(tag).to receive(:checks).and_return(tag_checks)

    delete "/tags/#{tag.id}/links/checks", Flapjack.dump_json(:data => [{
      :type => 'check', :id => check.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'adds a rule to a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Rule, Flapjack::Data::Check, Flapjack::Data::Contact,
           Flapjack::Data::Route).and_yield

    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)

    expect(tag_rules).to receive(:add_ids).with(rule.id)
    expect(tag).to receive(:rules).and_return(tag_rules)

    post "/tags/#{tag.id}/links/rules", Flapjack.dump_json(:data => [{
      :type => 'rule', :id => rule.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'lists rules for a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Rule, Flapjack::Data::Check, Flapjack::Data::Contact,
           Flapjack::Data::Route).and_yield

    expect(tag_rules).to receive(:ids).and_return([rule.id])
    expect(tag).to receive(:rules).and_return(tag_rules)

    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)

    get "/tags/#{tag.id}/rules"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => [{:type => 'rule', :id => rule.id}],
      :links => {
        :self    => "http://example.org/tags/#{tag.id}/links/rules",
        :related => "http://example.org/tags/#{tag.id}/rules",
      }
    ))
  end

  it 'updates rules for a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Rule, Flapjack::Data::Check, Flapjack::Data::Contact,
           Flapjack::Data::Route).and_yield

    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)

    expect(tag_rules).to receive(:ids).and_return([])
    expect(tag_rules).to receive(:add_ids).with(rule.id)
    expect(tag).to receive(:rules).twice.and_return(tag_rules)

    patch "/tags/#{tag.id}/links/rules", Flapjack.dump_json(:data => [{
      :type => 'rule', :id => rule.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'deletes a rule from a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Rule, Flapjack::Data::Check, Flapjack::Data::Contact,
           Flapjack::Data::Route).and_yield

    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)

    expect(tag_rules).to receive(:remove_ids).with(rule.id)
    expect(tag).to receive(:rules).and_return(tag_rules)

    delete "/tags/#{tag.id}/links/rules", Flapjack.dump_json(:data => [{
      :type => 'rule', :id => rule.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

end
