require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::TagLinks', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:tag)       { double(Flapjack::Data::Tag, :id => tag_data[:id]) }
  let(:check)     { double(Flapjack::Data::Check, :id => check_data[:id]) }
  let(:contact)   { double(Flapjack::Data::Contact, :id => contact_data[:id]) }
  let(:rule)      { double(Flapjack::Data::Rule, :id => rule_data[:id]) }

  let(:tag_checks)   { double('tag_checks') }
  let(:tag_contacts) { double('tag_contacts') }
  let(:tag_rules)    { double('tag_rules') }

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

  it 'adds a check to a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Check).
      and_yield

    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)

    expect(tag_checks).to receive(:add_ids).with(check.id)
    expect(tag).to receive(:checks).and_return(tag_checks)

    post "/tags/#{tag.id}/relationships/checks", Flapjack.dump_json(:data => [{
      :type => 'check', :id => check.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'lists checks for a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Check).
      and_yield

    sorted = double('sorted')
    paged  = double('paged')
    expect(paged).to receive(:ids).and_return([check.id])
    expect(sorted).to receive(:page).with(1, :per_page => 20).and_return(paged)
    expect(sorted).to receive(:count).and_return(1)
    expect(tag_checks).to receive(:sort).with(:id => :asc).and_return(sorted)
    expect(tag).to receive(:checks).and_return(tag_checks)

    tags = double('tags', :all => [tag])
    expect(tags).to receive(:empty?).and_return(false)
    expect(Flapjack::Data::Tag).to receive(:intersect).
      with(:id => tag.id).and_return(tags)

    get "/tags/#{tag.id}/checks"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => [{:type => 'check', :id => check.id}],
      :links => {
        :self    => "http://example.org/tags/#{tag.id}/relationships/checks",
        :related => "http://example.org/tags/#{tag.id}/checks",
      },
      :meta => meta
    ))
  end

  it 'updates checks for a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Check).
      and_yield

    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)

    expect(tag_checks).to receive(:ids).and_return([])
    expect(tag_checks).to receive(:add_ids).with(check.id)
    expect(tag).to receive(:checks).twice.and_return(tag_checks)

    patch "/tags/#{tag.id}/relationships/checks", Flapjack.dump_json(:data => [{
      :type => 'check', :id => check.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'deletes a check from a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Check).
      and_yield

    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)

    expect(tag_checks).to receive(:remove_ids).with(check.id)
    expect(tag).to receive(:checks).and_return(tag_checks)

    delete "/tags/#{tag.id}/relationships/checks", Flapjack.dump_json(:data => [{
      :type => 'check', :id => check.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'adds a contact to a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Contact).
      and_yield

    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)

    expect(tag_contacts).to receive(:add_ids).with(contact.id)
    expect(tag).to receive(:contacts).and_return(tag_contacts)

    post "/tags/#{tag.id}/relationships/contacts", Flapjack.dump_json(:data => [{
      :type => 'contact', :id => contact.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'lists contacts for a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Contact).
      and_yield

    sorted = double('sorted')
    paged  = double('paged')
    expect(paged).to receive(:ids).and_return([contact.id])
    expect(sorted).to receive(:page).with(1, :per_page => 20).and_return(paged)
    expect(sorted).to receive(:count).and_return(1)
    expect(tag_contacts).to receive(:sort).with(:id => :asc).and_return(sorted)
    expect(tag).to receive(:contacts).and_return(tag_contacts)

    tags = double('tags', :all => [tag])
    expect(tags).to receive(:empty?).and_return(false)
    expect(Flapjack::Data::Tag).to receive(:intersect).
      with(:id => tag.id).and_return(tags)

    get "/tags/#{tag.id}/contacts"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => [{:type => 'contact', :id => contact.id}],
      :links => {
        :self    => "http://example.org/tags/#{tag.id}/relationships/contacts",
        :related => "http://example.org/tags/#{tag.id}/contacts",
      },
      :meta => meta
    ))
  end

  it 'updates contacts for a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Contact).
      and_yield

    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)

    expect(tag_contacts).to receive(:ids).and_return([])
    expect(tag_contacts).to receive(:add_ids).with(contact.id)
    expect(tag).to receive(:contacts).twice.and_return(tag_contacts)

    patch "/tags/#{tag.id}/relationships/contacts", Flapjack.dump_json(:data => [{
      :type => 'contact', :id => contact.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'deletes a contact from a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Contact).
      and_yield

    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)

    expect(tag_contacts).to receive(:remove_ids).with(contact.id)
    expect(tag).to receive(:contacts).and_return(tag_contacts)

    delete "/tags/#{tag.id}/relationships/contacts", Flapjack.dump_json(:data => [{
      :type => 'contact', :id => contact.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'adds a rule to a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Rule).
      and_yield

    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)

    expect(tag_rules).to receive(:add_ids).with(rule.id)
    expect(tag).to receive(:rules).and_return(tag_rules)

    post "/tags/#{tag.id}/relationships/rules", Flapjack.dump_json(:data => [{
      :type => 'rule', :id => rule.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'lists rules for a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Rule).
      and_yield

    sorted = double('sorted')
    paged  = double('paged')
    expect(paged).to receive(:ids).and_return([rule.id])
    expect(sorted).to receive(:page).with(1, :per_page => 20).and_return(paged)
    expect(sorted).to receive(:count).and_return(1)
    expect(tag_rules).to receive(:sort).with(:id => :asc).and_return(sorted)
    expect(tag).to receive(:rules).and_return(tag_rules)

    tags = double('tags', :all => [tag])
    expect(tags).to receive(:empty?).and_return(false)
    expect(Flapjack::Data::Tag).to receive(:intersect).
      with(:id => tag.id).and_return(tags)

    get "/tags/#{tag.id}/rules"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => [{:type => 'rule', :id => rule.id}],
      :links => {
        :self    => "http://example.org/tags/#{tag.id}/relationships/rules",
        :related => "http://example.org/tags/#{tag.id}/rules",
      },
      :meta => meta
    ))
  end

  it 'updates rules for a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Rule).
      and_yield

    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)

    expect(tag_rules).to receive(:ids).and_return([])
    expect(tag_rules).to receive(:add_ids).with(rule.id)
    expect(tag).to receive(:rules).twice.and_return(tag_rules)

    patch "/tags/#{tag.id}/relationships/rules", Flapjack.dump_json(:data => [{
      :type => 'rule', :id => rule.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'deletes a rule from a tag' do
    expect(Flapjack::Data::Tag).to receive(:lock).
      with(Flapjack::Data::Rule).
      and_yield

    expect(Flapjack::Data::Tag).to receive(:find_by_id!).with(tag.id).
      and_return(tag)

    expect(tag_rules).to receive(:remove_ids).with(rule.id)
    expect(tag).to receive(:rules).and_return(tag_rules)

    delete "/tags/#{tag.id}/relationships/rules", Flapjack.dump_json(:data => [{
      :type => 'rule', :id => rule.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

end
