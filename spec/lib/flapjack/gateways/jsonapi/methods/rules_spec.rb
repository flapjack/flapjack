require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::Rules', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:rule)    { double(Flapjack::Data::Rule, :id => rule_data[:id]) }
  let(:rule_2)  { double(Flapjack::Data::Rule, :id => rule_2_data[:id]) }

  let(:contact) { double(Flapjack::Data::Contact, :id => contact_data[:id]) }

  let(:medium)  { double(Flapjack::Data::Medium, :id => email_data[:id]) }

  it "creates a rule" do
    expect(Flapjack::Data::Rule).to receive(:lock).with(no_args).and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => [rule_data[:id]]).and_return(empty_ids)

    expect(rule).to receive(:invalid?).and_return(false)
    expect(rule).to receive(:save).and_return(true)
    expect(Flapjack::Data::Rule).to receive(:new).with(rule_data).
      and_return(rule)

    expect(Flapjack::Data::Rule).to receive(:jsonapi_type).and_return('rule')

    post "/rules", Flapjack.dump_json(:data => {:rules => rule_data.merge(:type => 'rule')}), jsonapi_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data => {
      :rules => rule_data.merge(
        :type => 'rule',
        :links => {:self  => "http://example.org/rules/#{rule.id}",
                   :contact => "http://example.org/rules/#{rule.id}/contact",
                   :media => "http://example.org/rules/#{rule.id}/media",
                   :tags => "http://example.org/rules/#{rule.id}/tags"})
    }))
  end

  it "does not create a rule if the data is improperly formatted" do
    expect(Flapjack::Data::Rule).to receive(:lock).with(no_args).and_yield
    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => [rule_data[:id]]).and_return(empty_ids)

    errors = double('errors', :full_messages => ['err'])
    expect(rule).to receive(:errors).and_return(errors)

    expect(rule).to receive(:invalid?).and_return(true)
    expect(rule).not_to receive(:save)
    expect(Flapjack::Data::Rule).to receive(:new).with(rule_data).
      and_return(rule)

    post "/rules", Flapjack.dump_json(:data => {:rules => rule_data.merge(:type => 'rule')}), jsonapi_env
    expect(last_response.status).to eq(403)
  end

  it "gets all rules" do
    meta = {
      :pagination => {
        :page        => 1,
        :per_page    => 20,
        :total_pages => 1,
        :total_count => 1
      }
    }

    links = {
      :self  => 'http://example.org/rules',
      :first => 'http://example.org/rules?page=1',
      :last  => 'http://example.org/rules?page=1'
    }

    expect(Flapjack::Data::Rule).to receive(:count).and_return(1)

    page = double('page', :all => [rule])
    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).
      and_return(page)
    expect(Flapjack::Data::Rule).to receive(:sort).
      with(:id).and_return(sorted)

    expect(rule).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(rule_data)

    get '/rules'
    expect(last_response).to be_ok

    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data => {
      :rules => [rule_data.merge(
        :type => 'rule',
        :links => {:self  => "http://example.org/rules/#{rule.id}",
                   :contact => "http://example.org/rules/#{rule.id}/contact",
                   :media => "http://example.org/rules/#{rule.id}/media",
                   :tags => "http://example.org/rules/#{rule.id}/tags"})]
    }, :links => links, :meta => meta))
  end

  it "gets a single rule" do
    expect(Flapjack::Data::Rule).to receive(:find_by_id!).
      with(rule.id).and_return(rule)

    expect(rule).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(rule_data)

    get "/rules/#{rule.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data => {
      :rules => rule_data.merge(
        :type => 'rule',
        :links => {:self  => "http://example.org/rules/#{rule.id}",
                   :contact => "http://example.org/rules/#{rule.id}/contact",
                   :media => "http://example.org/rules/#{rule.id}/media",
                   :tags => "http://example.org/rules/#{rule.id}/tags"})
    }, :links => {:self  => "http://example.org/rules/#{rule.id}"}))
  end

  it "does not get a rule that does not exist" do
    expect(Flapjack::Data::Rule).to receive(:find_by_id!).
      with(rule.id).
      and_raise(Zermelo::Records::Errors::RecordNotFound.new(Flapjack::Data::Rule, rule.id))

    get "/rules/#{rule.id}"
    expect(last_response).to be_not_found
  end

  it "retrieves a rule and its linked contact record" do
    expect(Flapjack::Data::Rule).to receive(:find_by_id!).
      with(rule.id).and_return(rule)

    rules = double('rules')
    expect(rules).to receive(:associated_ids_for).with(:contact).twice.
      and_return(rule.id => contact.id)
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => [rule.id]).twice.and_return(rules)

    contacts = double('contacts')
    expect(contacts).to receive(:collect) {|&arg| [arg.call(contact)] }
    expect(Flapjack::Data::Contact).to receive(:intersect).
      with(:id => [contact_data[:id]]).and_return(contacts)

    expect(contact).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(contact_data)

    expect(rule).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(rule_data)

    get "/rules/#{rule.id}?include=contact"
    expect(last_response).to be_ok

    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data => {
      :rules => rule_data.merge(
        :type => 'rule',
        :links => {:self  => "http://example.org/rules/#{rule.id}",
                   :contact =>  {
                    :self => "http://example.org/rules/#{rule.id}/links/contact",
                    :related => "http://example.org/rules/#{rule.id}/contact",
                    :type => "contact",
                    :id => contact.id
                   },
                   :media => "http://example.org/rules/#{rule.id}/media",
                   :tags => "http://example.org/rules/#{rule.id}/tags"})
    }, :included => [
      contact_data.merge(:type => 'contact', :links => {
        :self => "http://example.org/contacts/#{contact.id}",
        :media => "http://example.org/contacts/#{contact.id}/media",
        :rules => "http://example.org/contacts/#{contact.id}/rules"
      }
    )], :links => {:self  => "http://example.org/rules/#{rule.id}?include=contact"}))
  end

  it "retrieves a rule and all its contact's media records" do
    expect(Flapjack::Data::Rule).to receive(:find_by_id!).
      with(rule.id).and_return(rule)

    rules = double('rules')
    expect(rules).to receive(:associated_ids_for).with(:contact).
      and_return(rule.id => contact.id)
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => [rule.id]).and_return(rules)

    contacts = double('contacts')
    expect(contacts).to receive(:associated_ids_for).with(:media).and_return({contact.id => [medium.id]})
    expect(Flapjack::Data::Contact).to receive(:intersect).
      with(:id => [contact_data[:id]]).and_return(contacts)

    media = double('media')
    expect(media).to receive(:collect) {|&arg| [arg.call(medium)] }
    expect(Flapjack::Data::Medium).to receive(:intersect).
      with(:id => [medium.id]).and_return(media)

    expect(medium).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(email_data)

    expect(rule).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(rule_data)

    get "/rules/#{rule.id}?include=contact.media"
    expect(last_response).to be_ok
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data => {
      :rules => rule_data.merge(
        :type => 'rule',
        :links => {:self    => "http://example.org/rules/#{rule.id}",
                   :contact => "http://example.org/rules/#{rule.id}/contact",
                   :media   => "http://example.org/rules/#{rule.id}/media",
                   :tags    => "http://example.org/rules/#{rule.id}/tags"})
    }, :included => [
      email_data.merge(:type => 'medium', :links => {
        :self => "http://example.org/media/#{medium.id}",
        :contact => "http://example.org/media/#{medium.id}/contact",
        :rules => "http://example.org/media/#{medium.id}/rules"
      }
    )], :links => {:self  => "http://example.org/rules/#{rule.id}?include=contact.media"}))
  end

  it "retrieves a rule, its contact, and the contact's media records" do
    expect(Flapjack::Data::Rule).to receive(:find_by_id!).
      with(rule.id).and_return(rule)

    rules = double('rules')
    expect(rules).to receive(:associated_ids_for).with(:contact).twice.
      and_return(rule.id => contact.id)
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => [rule.id]).twice.and_return(rules)

    contacts = double('contacts')
    expect(contacts).to receive(:associated_ids_for).with(:media). #twice.
      and_return({contact.id => [medium.id]})
    expect(contacts).to receive(:collect) {|&arg| [arg.call(contact)] }
    expect(Flapjack::Data::Contact).to receive(:intersect).twice.
      with(:id => [contact_data[:id]]).and_return(contacts)

    media = double('media')
    expect(media).to receive(:collect) {|&arg| [arg.call(medium)] }
    expect(Flapjack::Data::Medium).to receive(:intersect).
      with(:id => [medium.id]).and_return(media)

    expect(contact).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(contact_data)

    expect(medium).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(email_data)

    expect(rule).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(rule_data)

    get "/rules/#{rule.id}?include=contact%2Ccontact.media"
    expect(last_response).to be_ok
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data => {
      :rules => rule_data.merge(
        :type => 'rule',
        :links => {:self    => "http://example.org/rules/#{rule.id}",
                   :contact => {
                     :self    => "http://example.org/rules/#{rule.id}/links/contact",
                     :related => "http://example.org/rules/#{rule.id}/contact",
                     :type    => 'contact'
                   },
                   :media   => "http://example.org/rules/#{rule.id}/media",
                   :tags    => "http://example.org/rules/#{rule.id}/tags"})
    }, :included => [
      contact_data.merge(:type => 'contact', :links => {
        :self => "http://example.org/contacts/#{contact.id}",
        :media => "http://example.org/contacts/#{contact.id}/media",
        :rules => "http://example.org/contacts/#{contact.id}/rules"
      }),
      email_data.merge(:type => 'medium', :links => {
        :self => "http://example.org/media/#{medium.id}",
        :contact => "http://example.org/media/#{medium.id}/contact",
        :rules => "http://example.org/media/#{medium.id}/rules"
      }
    )], :links => {:self  => "http://example.org/rules/#{rule.id}?include=contact%2Ccontact.media"}))
  end

  it "sets a contact for a rule" do
    expect(Flapjack::Data::Rule).to receive(:find_by_ids!).
      with(rule.id).and_return([rule])

    expect(Flapjack::Data::Contact).to receive(:find_by_id!).with(contact_data[:id]).
      and_return(contact)

    expect(rule).to receive(:invalid?).and_return(false)
    expect(rule).to receive(:save).and_return(true)

    expect(rule).to receive(:contact=).with(contact)

    patch "/rules/#{rule.id}",
      Flapjack.dump_json(:data => {:rules => {:id => rule.id, :type => 'rule', :links =>
        {:contact => {:type => 'contact', :id => contact.id}}}}),
      jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it "sets a contact for multiple rules" do
    expect(Flapjack::Data::Rule).to receive(:find_by_ids!).
      with(rule.id, rule_2.id).and_return([rule, rule_2])

    expect(Flapjack::Data::Contact).to receive(:find_by_id!).with(contact_data[:id]).
      twice.and_return(contact)

    expect(rule).to receive(:invalid?).and_return(false)
    expect(rule).to receive(:save).and_return(true)

    expect(rule_2).to receive(:invalid?).and_return(false)
    expect(rule_2).to receive(:save).and_return(true)

    expect(rule).to receive(:contact=).with(contact)
    expect(rule_2).to receive(:contact=).with(contact)

    patch "/rules/#{rule.id},#{rule_2.id}",
      Flapjack.dump_json(:data => {:rules => [
        {:id => rule.id, :type => 'rule', :links =>
          {:contact => {:type => 'contact', :id => contact.id}}},
        {:id => rule_2.id, :type => 'rule', :links =>
          {:contact => {:type => 'contact', :id => contact.id}}}
        ]}),
      jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it "does not set a contact for a rule that does not exist" do
    expect(Flapjack::Data::Rule).to receive(:find_by_ids!).
      with(rule.id).
      and_raise(Zermelo::Records::Errors::RecordsNotFound.new(Flapjack::Data::Rule, [rule.id]))

    patch "/rules/#{rule.id}",
      Flapjack.dump_json(:data => {:rules => {:id => rule.id, :type => 'rule', :links =>
        {:contact => {:type => 'contact', :id => contact.id}}}}),
      jsonapi_env
    expect(last_response.status).to eq(404)
  end

  it "deletes a rule" do
    expect(Flapjack::Data::Rule).to receive(:lock).
      with(Flapjack::Data::Contact, Flapjack::Data::Medium, Flapjack::Data::Tag,
           Flapjack::Data::Route, Flapjack::Data::Check).
      and_yield

    rules = double('rules')
    expect(rules).to receive(:ids).and_return([rule.id])
    expect(rules).to receive(:destroy_all)
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => [rule.id]).and_return(rules)

    delete "/rules/#{rule.id}"
    expect(last_response.status).to eq(204)
  end

  it "deletes multiple rules" do
    expect(Flapjack::Data::Rule).to receive(:lock).
      with(Flapjack::Data::Contact, Flapjack::Data::Medium, Flapjack::Data::Tag,
           Flapjack::Data::Route, Flapjack::Data::Check).
      and_yield

    rules = double('rules')
    expect(rules).to receive(:ids).
      and_return([rule.id, rule_2.id])
    expect(rules).to receive(:destroy_all)
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => [rule.id, rule_2.id]).
      and_return(rules)

    delete "/rules/#{rule.id},#{rule_2.id}"
    expect(last_response.status).to eq(204)
  end

  it "does not delete a rule that does not exist" do
    expect(Flapjack::Data::Rule).to receive(:lock).
      with(Flapjack::Data::Contact, Flapjack::Data::Medium, Flapjack::Data::Tag,
           Flapjack::Data::Route, Flapjack::Data::Check).
      and_yield

    rules = double('rules')
    expect(rules).to receive(:ids).and_return([])
    expect(rules).not_to receive(:destroy_all)
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => [rule.id]).and_return(rules)

    delete "/rules/#{rule.id}"
    expect(last_response).to be_not_found
  end

end
