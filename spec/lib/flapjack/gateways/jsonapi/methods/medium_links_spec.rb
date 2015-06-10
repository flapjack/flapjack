require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::MediumLinks', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:medium)  { double(Flapjack::Data::Medium, :id => email_data[:id]) }
  let(:contact) { double(Flapjack::Data::Contact, :id => contact_data[:id]) }
  let(:rule)    { double(Flapjack::Data::Rule, :id => rule_data[:id]) }

  let(:medium_rules)  { double('medium_rules') }

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

  it 'shows the contact for a medium' do
    expect(Flapjack::Data::Medium).to receive(:lock).
      with(Flapjack::Data::Contact).and_yield

    expect(medium).to receive(:contact).and_return(contact)

    media = double('media', :all => [medium])
    expect(media).to receive(:empty?).and_return(false)
    expect(Flapjack::Data::Medium).to receive(:intersect).
      with(:id => medium.id).and_return(media)

    get "/media/#{medium.id}/contact"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => {:type => 'contact', :id => contact.id},
      :links => {
        :self    => "http://example.org/media/#{medium.id}/relationships/contact",
        :related => "http://example.org/media/#{medium.id}/contact",
      }
    ))
  end

  it 'cannot change the contact for a medium' do
    patch "/media/#{medium.id}/relationships/contact", Flapjack.dump_json(
      :data => {
        :type => 'contact',
        :id   => contact.id,
      }
    ), jsonapi_env
    expect(last_response.status).to eq(404)
  end

  it 'cannot clear the contact for a medium' do
    patch "/media/#{medium.id}/relationships/contact", Flapjack.dump_json(
      :data => {
        :type => 'contact',
        :id   => nil,
      }
    ), jsonapi_env
    expect(last_response.status).to eq(404)
  end

  it 'adds a rule to a medium' do
    expect(Flapjack::Data::Medium).to receive(:lock).
      with(Flapjack::Data::Rule).and_yield

    expect(Flapjack::Data::Medium).to receive(:find_by_id!).with(medium.id).
      and_return(medium)

    expect(medium_rules).to receive(:add_ids).with(rule.id)
    expect(medium).to receive(:rules).and_return(medium_rules)

    post "/media/#{medium.id}/relationships/rules", Flapjack.dump_json(
      :data => [{:type => 'rule', :id => rule.id}]), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'lists rules for a medium' do
    expect(Flapjack::Data::Medium).to receive(:lock).
      with(Flapjack::Data::Rule).and_yield

    sorted = double('sorted')
    paged  = double('paged')
    expect(paged).to receive(:ids).and_return([rule.id])
    expect(sorted).to receive(:page).with(1, :per_page => 20).and_return(paged)
    expect(sorted).to receive(:count).and_return(1)
    expect(medium_rules).to receive(:sort).with(:id => :asc).and_return(sorted)
    expect(medium).to receive(:rules).and_return(medium_rules)

    media = double('media', :all => [medium])
    expect(media).to receive(:empty?).and_return(false)
    expect(Flapjack::Data::Medium).to receive(:intersect).
      with(:id => medium.id).and_return(media)

    get "/media/#{medium.id}/rules"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => [{:type => 'rule', :id => rule.id}],
      :links => {
        :self    => "http://example.org/media/#{medium.id}/relationships/rules",
        :related => "http://example.org/media/#{medium.id}/rules",
      },
      :meta => meta
    ))
  end

  it 'updates rules for a medium' do
    expect(Flapjack::Data::Medium).to receive(:lock).
      with(Flapjack::Data::Rule).and_yield

    expect(Flapjack::Data::Medium).to receive(:find_by_id!).with(medium.id).
      and_return(medium)

    expect(medium_rules).to receive(:ids).and_return([])
    expect(medium_rules).to receive(:add_ids).with(rule.id)
    expect(medium).to receive(:rules).twice.and_return(medium_rules)

    patch "/media/#{medium.id}/relationships/rules", Flapjack.dump_json(
      :data => [
        {:type => 'rule', :id => rule.id}
      ]
    ), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'clears rules for a medium' do
    expect(Flapjack::Data::Medium).to receive(:lock).
      with(Flapjack::Data::Rule).and_yield

    expect(Flapjack::Data::Medium).to receive(:find_by_id!).with(medium.id).
      and_return(medium)

    expect(medium_rules).to receive(:ids).and_return([rule.id])
    expect(medium_rules).to receive(:remove_ids).with(rule.id)
    expect(medium).to receive(:rules).twice.and_return(medium_rules)

    patch "/media/#{medium.id}/relationships/rules", Flapjack.dump_json(
      :data => []
    ), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'deletes a rule from a medium' do
    expect(Flapjack::Data::Medium).to receive(:lock).
      with(Flapjack::Data::Rule).and_yield

    expect(Flapjack::Data::Medium).to receive(:find_by_id!).with(medium.id).
      and_return(medium)

    expect(medium_rules).to receive(:remove_ids).with(rule.id)
    expect(medium).to receive(:rules).and_return(medium_rules)

    delete "/media/#{medium.id}/relationships/rules", Flapjack.dump_json(
      :data => [{:type => 'rule', :id => rule.id}]
    ), jsonapi_env
    expect(last_response.status).to eq(204)
  end

end
