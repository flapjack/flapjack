require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::ContactLinks', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:contact)  { double(Flapjack::Data::Contact, :id => contact_data[:id]) }
  let(:medium)   { double(Flapjack::Data::Medium, :id => email_data[:id]) }
  let(:rule)     { double(Flapjack::Data::Rule, :id => rule_data[:id]) }
  let(:tag)      { double(Flapjack::Data::Tag, :id => tag_data[:id]) }

  let(:contact_media)  { double('contact_media') }
  let(:contact_rules)  { double('contact_rules') }
  let(:contact_tags)  { double('contact_tags') }

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

  it 'lists media for a contact' do
    expect(Flapjack::Data::Contact).to receive(:lock).
      with(Flapjack::Data::Medium).and_yield

    sorted = double('sorted')
    paged  = double('paged')
    expect(paged).to receive(:ids).and_return([medium.id])
    expect(sorted).to receive(:page).with(1, :per_page => 20).and_return(paged)
    expect(sorted).to receive(:count).and_return(1)
    expect(contact_media).to receive(:sort).with(:id => :asc).and_return(sorted)
    expect(contact).to receive(:media).and_return(contact_media)

    contacts = double('contacts', :all => [contact])
    expect(contacts).to receive(:empty?).and_return(false)
    expect(Flapjack::Data::Contact).to receive(:intersect).
      with(:id => contact.id).and_return(contacts)

    get "/contacts/#{contact.id}/media"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => [{:type => 'medium', :id => medium.id}],
      :links => {
        :self    => "http://example.org/contacts/#{contact.id}/relationships/media",
        :related => "http://example.org/contacts/#{contact.id}/media",
      },
      :meta => meta
    ))
  end

  it 'lists rules for a contact' do
    expect(Flapjack::Data::Contact).to receive(:lock).
      with(Flapjack::Data::Rule).and_yield

    sorted = double('sorted')
    paged  = double('paged')
    expect(paged).to receive(:ids).and_return([rule.id])
    expect(sorted).to receive(:page).with(1, :per_page => 20).and_return(paged)
    expect(sorted).to receive(:count).and_return(1)
    expect(contact_rules).to receive(:sort).with(:id => :asc).and_return(sorted)
    expect(contact).to receive(:rules).and_return(contact_rules)

    contacts = double('contacts', :all => [contact])
    expect(contacts).to receive(:empty?).and_return(false)
    expect(Flapjack::Data::Contact).to receive(:intersect).
      with(:id => contact.id).and_return(contacts)

    get "/contacts/#{contact.id}/rules"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => [{:type => 'rule', :id => rule.id}],
      :links => {
        :self    => "http://example.org/contacts/#{contact.id}/relationships/rules",
        :related => "http://example.org/contacts/#{contact.id}/rules",
      },
      :meta => meta
    ))
  end

  it 'adds tags to a contact' do
    expect(Flapjack::Data::Contact).to receive(:lock).
      with(Flapjack::Data::Tag).
      and_yield

    expect(Flapjack::Data::Contact).to receive(:find_by_id!).with(contact.id).
      and_return(contact)

    expect(contact_tags).to receive(:add_ids).with(tag.id)
    expect(contact).to receive(:tags).and_return(contact_tags)

    post "/contacts/#{contact.id}/relationships/tags", Flapjack.dump_json(:data => [{
      :type => 'tag', :id => tag.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'lists tags for a contact' do
    expect(Flapjack::Data::Contact).to receive(:lock).
      with(Flapjack::Data::Tag).
      and_yield

    sorted = double('sorted')
    paged  = double('paged')
    expect(paged).to receive(:ids).and_return([tag.id])
    expect(sorted).to receive(:page).with(1, :per_page => 20).and_return(paged)
    expect(sorted).to receive(:count).and_return(1)
    expect(contact_tags).to receive(:sort).with(:id => :asc).and_return(sorted)
    expect(contact).to receive(:tags).and_return(contact_tags)

    contacts = double('contacts', :all => [contact])
    expect(contacts).to receive(:empty?).and_return(false)
    expect(Flapjack::Data::Contact).to receive(:intersect).
      with(:id => contact.id).and_return(contacts)

    get "/contacts/#{contact.id}/tags"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => [{:type => 'tag', :id => tag.id}],
      :links => {
        :self    => "http://example.org/contacts/#{contact.id}/relationships/tags",
        :related => "http://example.org/contacts/#{contact.id}/tags",
      },
      :meta => meta
    ))
  end

  it 'lists tags for a contact, including tag data' do
    expect(Flapjack::Data::Contact).to receive(:lock).
      with(Flapjack::Data::Tag).
      and_yield

    sorted = double('sorted')
    paged  = double('paged')
    expect(paged).to receive(:ids).and_return([tag.id])
    expect(sorted).to receive(:page).with(1, :per_page => 20).and_return(paged)
    expect(sorted).to receive(:count).and_return(1)
    expect(contact_tags).to receive(:sort).with(:id => :asc).and_return(sorted)
    expect(contact).to receive(:tags).and_return(contact_tags)

    full_tags = double('full_tags')
    expect(full_tags).to receive(:collect) {|&arg| [arg.call(tag)] }

    expect(Flapjack::Data::Tag).to receive(:intersect).
      with(:id => [tag.id]).and_return(full_tags)

    expect(tag).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(tag_data.merge(:id => tag.id))

    contacts = double('contacts', :all => [contact])
    expect(contacts).to receive(:empty?).and_return(false)
    expect(contacts).to receive(:associated_ids_for).with(:tags).
      and_return(contact.id => [tag.id])
    expect(contacts).to receive(:ids).and_return(Set.new([contact.id]))
    expect(Flapjack::Data::Contact).to receive(:intersect).
      with(:id => Set.new([contact.id])).and_return(contacts)
    expect(Flapjack::Data::Contact).to receive(:intersect).
      with(:id => contact.id).and_return(contacts)

    get "/contacts/#{contact.id}/tags?include=tags"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => [{:type => 'tag', :id => tag.id}],
      :included => [{
        :id => tag.id,
        :type => 'tag',
        :attributes => tag_data.reject {|k,v| :id.eql?(k) }
      }],
      :links => {
        :self    => "http://example.org/contacts/#{contact.id}/relationships/tags",
        :related => "http://example.org/contacts/#{contact.id}/tags",
      },
      :meta => meta
    ))
  end

  it 'updates tags for a contact' do
    expect(Flapjack::Data::Contact).to receive(:lock).
      with(Flapjack::Data::Tag).
      and_yield

    expect(Flapjack::Data::Contact).to receive(:find_by_id!).with(contact.id).
      and_return(contact)

    expect(contact_tags).to receive(:ids).and_return([])
    expect(contact_tags).to receive(:add_ids).with(tag.id)
    expect(contact).to receive(:tags).twice.and_return(contact_tags)

    patch "/contacts/#{contact.id}/relationships/tags", Flapjack.dump_json(:data => [{
      :type => 'tag', :id => tag.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'deletes a tag from a contact' do
    expect(Flapjack::Data::Contact).to receive(:lock).
      with(Flapjack::Data::Tag).
      and_yield

    expect(Flapjack::Data::Contact).to receive(:find_by_id!).with(contact.id).
      and_return(contact)

    expect(contact_tags).to receive(:remove_ids).with(tag.id)
    expect(contact).to receive(:tags).and_return(contact_tags)

    delete "/contacts/#{contact.id}/relationships/tags", Flapjack.dump_json(:data => [{
      :type => 'tag', :id => tag.id
    }]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

end
