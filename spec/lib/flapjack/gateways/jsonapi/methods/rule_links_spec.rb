require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::RuleLinks', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:rule)    { double(Flapjack::Data::Rule, :id => rule_data[:id]) }
  let(:contact) { double(Flapjack::Data::Contact, :id => contact_data[:id]) }
  let(:tag)     { double(Flapjack::Data::Tag, :id => tag_data[:id]) }
  let(:medium)  { double(Flapjack::Data::Medium, :id => sms_data[:id]) }

  let(:rule_tags)  { double('rule_tags') }
  let(:rule_media) { double('rule_media') }

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

  it 'shows the contact for a rule' do
    expect(Flapjack::Data::Rule).to receive(:lock).
      with(Flapjack::Data::Contact).and_yield

    expect(rule).to receive(:contact).and_return(contact)

    rules = double('rule', :all => [rule])
    expect(rules).to receive(:empty?).and_return(false)
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => rule.id).and_return(rules)

    get "/rules/#{rule.id}/contact"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => {:type => 'contact', :id => contact.id},
      :links => {
        :self    => "http://example.org/rules/#{rule.id}/relationships/contact",
        :related => "http://example.org/rules/#{rule.id}/contact",
      }
    ))
  end

  it 'cannot change the contact for a rule' do
    patch "/rules/#{rule.id}/relationships/contact", Flapjack.dump_json(:data => {
      :type => 'contact', :id => contact.id
    }), jsonapi_env
    expect(last_response.status).to eq(404)
  end

  it 'adds a medium to a rule' do
    expect(Flapjack::Data::Rule).to receive(:lock).
      with(Flapjack::Data::Medium).and_yield

    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule.id).
      and_return(rule)

    expect(rule_media).to receive(:add_ids).with(medium.id)
    expect(rule).to receive(:media).and_return(rule_media)

    post "/rules/#{rule.id}/relationships/media", Flapjack.dump_json(:data => [{
      :type => 'medium', :id => medium.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'lists media for a rule' do
    expect(Flapjack::Data::Rule).to receive(:lock).
      with(Flapjack::Data::Medium).and_yield

    sorted = double('sorted')
    paged  = double('paged')
    expect(paged).to receive(:ids).and_return([medium.id])
    expect(sorted).to receive(:page).with(1, :per_page => 20).and_return(paged)
    expect(sorted).to receive(:count).and_return(1)
    expect(rule_media).to receive(:sort).with(:id => :asc).and_return(sorted)
    expect(rule).to receive(:media).and_return(rule_media)

    rules = double('rule', :all => [rule])
    expect(rules).to receive(:empty?).and_return(false)
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => rule.id).and_return(rules)

    get "/rules/#{rule.id}/media"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => [{:type => 'medium', :id => medium.id}],
      :links => {
        :self    => "http://example.org/rules/#{rule.id}/relationships/media",
        :related => "http://example.org/rules/#{rule.id}/media",
      },
      :meta => meta
    ))
  end

  it 'updates media for a rule' do
    expect(Flapjack::Data::Rule).to receive(:lock).
      with(Flapjack::Data::Medium).and_yield

    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule.id).
      and_return(rule)

    expect(rule_media).to receive(:ids).and_return([])
    expect(rule_media).to receive(:add_ids).with(medium.id)
    expect(rule).to receive(:media).twice.and_return(rule_media)

    patch "/rules/#{rule.id}/relationships/media", Flapjack.dump_json(:data => [{
      :type => 'medium', :id => medium.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'deletes a medium from a rule' do
    expect(Flapjack::Data::Rule).to receive(:lock).
      with(Flapjack::Data::Medium).and_yield

    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule.id).
      and_return(rule)

    expect(rule_media).to receive(:remove_ids).with(medium.id)
    expect(rule).to receive(:media).and_return(rule_media)

    delete "/rules/#{rule.id}/relationships/media", Flapjack.dump_json(:data => [{
      :type => 'medium', :id => medium.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'adds tags to a rule' do
    expect(Flapjack::Data::Rule).to receive(:lock).
      with(Flapjack::Data::Tag).and_yield

    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule.id).
      and_return(rule)

    expect(rule_tags).to receive(:add_ids).with(tag.id)
    expect(rule).to receive(:tags).and_return(rule_tags)

    post "/rules/#{rule.id}/relationships/tags", Flapjack.dump_json(:data => [{
      :type => 'tag', :id => tag.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'lists tags for a rule' do
    expect(Flapjack::Data::Rule).to receive(:lock).
      with(Flapjack::Data::Tag).and_yield

    sorted = double('sorted')
    paged  = double('paged')
    expect(paged).to receive(:ids).and_return([tag.id])
    expect(sorted).to receive(:page).with(1, :per_page => 20).and_return(paged)
    expect(sorted).to receive(:count).and_return(1)
    expect(rule_tags).to receive(:sort).with(:id => :asc).and_return(sorted)
    expect(rule).to receive(:tags).and_return(rule_tags)

    rules = double('rule', :all => [rule])
    expect(rules).to receive(:empty?).and_return(false)
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => rule.id).and_return(rules)

    get "/rules/#{rule.id}/tags"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => [{:type => 'tag', :id => tag.id}],
      :links => {
        :self    => "http://example.org/rules/#{rule.id}/relationships/tags",
        :related => "http://example.org/rules/#{rule.id}/tags",
      },
      :meta => meta
    ))
  end

  it 'updates tags for a rule' do
    expect(Flapjack::Data::Rule).to receive(:lock).
      with(Flapjack::Data::Tag).and_yield

    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule.id).
      and_return(rule)

    expect(rule_tags).to receive(:ids).and_return([])
    expect(rule_tags).to receive(:add_ids).with(tag.id)
    expect(rule).to receive(:tags).twice.and_return(rule_tags)

    patch "/rules/#{rule.id}/relationships/tags", Flapjack.dump_json(:data => [{
      :type => 'tag', :id => tag.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'deletes a tag from a rule' do
    expect(Flapjack::Data::Rule).to receive(:lock).
      with(Flapjack::Data::Tag).and_yield

    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule.id).
      and_return(rule)

    expect(rule_tags).to receive(:remove_ids).with(tag.id)
    expect(rule).to receive(:tags).and_return(rule_tags)

    delete "/rules/#{rule.id}/relationships/tags", Flapjack.dump_json(:data => [{
      :type => 'tag', :id => tag.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

end
