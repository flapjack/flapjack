require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::ContactLinks', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:contact) { double(Flapjack::Data::Contact, :id => contact_data[:id]) }
  let(:medium)  { double(Flapjack::Data::Medium, :id => email_data[:id]) }
  let(:rule)    { double(Flapjack::Data::Rule, :id => rule_data[:id]) }

  let(:contact_media)  { double('contact_media') }
  let(:contact_rules)  { double('contact_rules') }

  it 'adds a medium to a contact' do
    expect(Flapjack::Data::Contact).to receive(:find_by_ids!).with(contact.id).
      and_return([contact])
    expect(Flapjack::Data::Medium).to receive(:find_by_ids!).with(medium.id).
      and_return([medium])

    expect(contact_media).to receive(:add).with(medium)
    expect(contact).to receive(:media).and_return(contact_media)

    post "/contacts/#{contact.id}/links/media", Flapjack.dump_json(:media => medium.id), jsonapi_post_env
    expect(last_response.status).to eq(204)
  end

  it 'lists media for a contact' do
    expect(contact_media).to receive(:ids).and_return([medium.id])
    expect(contact).to receive(:media).and_return(contact_media)

    expect(Flapjack::Data::Contact).to receive(:find_by_ids!).with(contact.id).
      and_return([contact])

    get "/contacts/#{contact.id}/links/media"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to eq(Flapjack.dump_json(:media => [medium.id]))
  end

  it 'updates media for a contact' do
    expect(Flapjack::Data::Contact).to receive(:find_by_ids!).with(contact.id).
      and_return([contact])
    expect(Flapjack::Data::Medium).to receive(:find_by_ids!).with(medium.id).
      and_return([medium])

    expect(contact_media).to receive(:ids).and_return([])
    expect(contact_media).to receive(:add).with(medium)
    expect(contact).to receive(:media).twice.and_return(contact_media)

    put "/contacts/#{contact.id}/links/media", Flapjack.dump_json(:media => [medium.id]), jsonapi_post_env
    expect(last_response.status).to eq(204)
  end

  it 'deletes a medium from a contact' do
    expect(Flapjack::Data::Contact).to receive(:find_by_ids!).with(contact.id).
      and_return([contact])

    expect(contact_media).to receive(:find_by_ids!).with(medium.id).
      and_return([medium])
    expect(contact_media).to receive(:delete).with(medium)
    expect(contact).to receive(:media).and_return(contact_media)

    delete "/contacts/#{contact.id}/links/media/#{medium.id}"
    expect(last_response.status).to eq(204)
  end

  it 'adds a rule to a contact' do
    expect(Flapjack::Data::Contact).to receive(:find_by_ids!).with(contact.id).
      and_return([contact])
    expect(Flapjack::Data::Rule).to receive(:find_by_ids!).with(rule.id).
      and_return([rule])

    expect(contact_rules).to receive(:add).with(rule)
    expect(contact).to receive(:rules).and_return(contact_rules)

    post "/contacts/#{contact.id}/links/rules", Flapjack.dump_json(:rules => rule.id), jsonapi_post_env
    expect(last_response.status).to eq(204)
  end

  it 'lists rules for a contact' do
    expect(contact_rules).to receive(:ids).and_return([rule.id])
    expect(contact).to receive(:rules).and_return(contact_rules)

    expect(Flapjack::Data::Contact).to receive(:find_by_ids!).with(contact.id).
      and_return([contact])

    get "/contacts/#{contact.id}/links/rules"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to eq(Flapjack.dump_json(:rules => [rule.id]))
  end

  it 'updates rules for a contact' do
    expect(Flapjack::Data::Contact).to receive(:find_by_ids!).with(contact.id).
      and_return([contact])
    expect(Flapjack::Data::Rule).to receive(:find_by_ids!).with(rule.id).
      and_return([rule])

    expect(contact_rules).to receive(:ids).and_return([])
    expect(contact_rules).to receive(:add).with(rule)
    expect(contact).to receive(:rules).twice.and_return(contact_rules)

    put "/contacts/#{contact.id}/links/rules", Flapjack.dump_json(:rules => [rule.id]), jsonapi_post_env
    expect(last_response.status).to eq(204)
  end

  it 'deletes a rule from a contact' do
    expect(Flapjack::Data::Contact).to receive(:find_by_ids!).with(contact.id).
      and_return([contact])

    expect(contact_rules).to receive(:find_by_ids!).with(rule.id).
      and_return([rule])
    expect(contact_rules).to receive(:delete).with(rule)
    expect(contact).to receive(:rules).and_return(contact_rules)

    delete "/contacts/#{contact.id}/links/rules/#{rule.id}"
    expect(last_response.status).to eq(204)
  end

end
