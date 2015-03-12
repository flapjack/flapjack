require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::RuleLinks', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:rule)    { double(Flapjack::Data::Rule, :id => rule_data[:id]) }
  let(:contact) { double(Flapjack::Data::Contact, :id => contact_data[:id]) }
  let(:tag)     { double(Flapjack::Data::Tag, :id => tag_data[:name]) }
  let(:medium)  { double(Flapjack::Data::Medium, :id => sms_data[:id]) }

  let(:rule_tags)  { double('rule_tags') }
  let(:rule_media) { double('rule_media') }

  it 'sets a contact for a rule' do
    expect(Flapjack::Data::Rule).to receive(:lock).
      with(Flapjack::Data::Contact).and_yield

    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule.id).
      and_return(rule)
    expect(Flapjack::Data::Contact).to receive(:find_by_id!).with(contact.id).
      and_return(contact)

    expect(rule).to receive(:contact).and_return(nil)
    expect(rule).to receive(:contact=).with(contact)

    post "/rules/#{rule.id}/links/contact", Flapjack.dump_json(:contact => contact.id), jsonapi_post_env
    expect(last_response.status).to eq(204)
  end

  it 'shows the contact for a rule' do
    expect(rule).to receive(:contact).and_return(contact)

    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule.id).
      and_return(rule)

    get "/rules/#{rule.id}/contact"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => {:type => 'contact', :id => contact.id},
      :links => {
        :self    => "http://example.org/rules/#{rule.id}/links/contact",
        :related => "http://example.org/rules/#{rule.id}/contact",
      }
    ))
  end

  it 'changes the contact for a rule' do
    expect(Flapjack::Data::Rule).to receive(:lock).
      with(Flapjack::Data::Contact).and_yield

    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule.id).
      and_return(rule)
    expect(Flapjack::Data::Contact).to receive(:find_by_id!).with(contact.id).
      and_return(contact)

    expect(rule).to receive(:contact=).with(contact)

    put "/rules/#{rule.id}/links/contact", Flapjack.dump_json(:contact => contact.id), jsonapi_put_env
    expect(last_response.status).to eq(204)
  end

  it 'clears the contact for a rule' do
    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule.id).
      and_return(rule)

    expect(rule).to receive(:contact).and_return(contact)
    expect(rule).to receive(:contact=).with(nil)

    delete "/rules/#{rule.id}/links/contact"
    expect(last_response.status).to eq(204)
  end

  it 'adds a medium to a rule' do
    expect(Flapjack::Data::Rule).to receive(:lock).
      with(Flapjack::Data::Medium).and_yield

    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule.id).
      and_return(rule)
    expect(Flapjack::Data::Medium).to receive(:find_by_ids!).with(medium.id).
      and_return([medium])

    expect(rule_media).to receive(:add).with(medium)
    expect(rule).to receive(:media).and_return(rule_media)

    post "/rules/#{rule.id}/links/media", Flapjack.dump_json(:media => medium.id), jsonapi_post_env
    expect(last_response.status).to eq(204)
  end

  it 'lists media for a rule' do
    expect(rule_media).to receive(:ids).and_return([medium.id])
    expect(rule).to receive(:media).and_return(rule_media)

    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule.id).
      and_return(rule)

    get "/rules/#{rule.id}/media"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => [{:type => 'medium', :id => medium.id}],
      :links => {
        :self    => "http://example.org/rules/#{rule.id}/links/media",
        :related => "http://example.org/rules/#{rule.id}/media",
      }
    ))
  end

  it 'updates media for a rule' do
    expect(Flapjack::Data::Rule).to receive(:lock).
      with(Flapjack::Data::Medium).and_yield

    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule.id).
      and_return(rule)
    expect(Flapjack::Data::Medium).to receive(:find_by_ids!).with(medium.id).
      and_return([medium])

    expect(rule_media).to receive(:ids).and_return([])
    expect(rule_media).to receive(:add).with(medium)
    expect(rule).to receive(:media).twice.and_return(rule_media)

    put "/rules/#{rule.id}/links/media", Flapjack.dump_json(:media => [medium.id]), jsonapi_put_env
    expect(last_response.status).to eq(204)
  end

  it 'deletes a medium from a rule' do
    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule.id).
      and_return(rule)

    expect(rule_media).to receive(:find_by_ids!).with(medium.id).
      and_return([medium])
    expect(rule_media).to receive(:delete).with(medium)
    expect(rule).to receive(:media).and_return(rule_media)

    delete "/rules/#{rule.id}/links/media/#{medium.id}"
    expect(last_response.status).to eq(204)
  end

  it 'adds tags to a rule' do
    expect(Flapjack::Data::Rule).to receive(:lock).
      with(Flapjack::Data::Tag, Flapjack::Data::Check,
           Flapjack::Data::Route).and_yield

    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule.id).
      and_return(rule)
    expect(Flapjack::Data::Tag).to receive(:find_by_ids!).with(tag.id).
      and_return([tag])

    expect(rule_tags).to receive(:add).with(tag)
    expect(rule).to receive(:tags).and_return(rule_tags)

    post "/rules/#{rule.id}/links/tags", Flapjack.dump_json(:tags => tag.id), jsonapi_post_env
    expect(last_response.status).to eq(204)
  end

  it 'lists tags for a rule' do
    expect(rule_tags).to receive(:ids).and_return([tag.id])
    expect(rule).to receive(:tags).and_return(rule_tags)

    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule.id).
      and_return(rule)

    get "/rules/#{rule.id}/tags"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => [{:type => 'tag', :id => tag.id}],
      :links => {
        :self    => "http://example.org/rules/#{rule.id}/links/tags",
        :related => "http://example.org/rules/#{rule.id}/tags",
      }
    ))
  end

  it 'updates tags for a rule' do
    expect(Flapjack::Data::Rule).to receive(:lock).
      with(Flapjack::Data::Tag, Flapjack::Data::Check,
           Flapjack::Data::Route).and_yield

    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule.id).
      and_return(rule)
    expect(Flapjack::Data::Tag).to receive(:find_by_ids!).with(tag.id).
      and_return([tag])

    expect(rule_tags).to receive(:ids).and_return([])
    expect(rule_tags).to receive(:add).with(tag)
    expect(rule).to receive(:tags).twice.and_return(rule_tags)

    put "/rules/#{rule.id}/links/tags", Flapjack.dump_json(:tags => [tag.id]), jsonapi_put_env
    expect(last_response.status).to eq(204)
  end

  it 'deletes a tag from a rule' do
    expect(Flapjack::Data::Rule).to receive(:find_by_id!).with(rule.id).
      and_return(rule)

    expect(rule_tags).to receive(:find_by_ids!).with(tag.id).
      and_return([tag])
    expect(rule_tags).to receive(:delete).with(tag)
    expect(rule).to receive(:tags).and_return(rule_tags)

    delete "/rules/#{rule.id}/links/tags/#{tag.id}"
    expect(last_response.status).to eq(204)
  end

end
