require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::Rules', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:rule)    { double(Flapjack::Data::Rule, :id => rule_data[:id]) }
  let(:rule_2)  { double(Flapjack::Data::Rule, :id => rule_2_data[:id]) }

  let(:contact) { double(Flapjack::Data::Contact, :id => contact_data[:id]) }

  let(:medium)  { double(Flapjack::Data::Medium, :id => email_data[:id]) }

  it "creates a rule" do
    expect(Flapjack::Data::Rule).to receive(:lock).with(Flapjack::Data::Contact,
      Flapjack::Data::Medium, Flapjack::Data::Tag, Flapjack::Data::Check,
      Flapjack::Data::Route).and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    full_ids = double('full_ids')
    expect(full_ids).to receive(:associated_ids_for).with(:contact).and_return({rule.id => nil})
    expect(full_ids).to receive(:associated_ids_for).with(:media).and_return({rule.id => []})
    expect(full_ids).to receive(:associated_ids_for).with(:tags).and_return({rule.id => []})
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => [rule_data[:id]]).exactly(4).times.and_return(empty_ids, full_ids)

    expect(rule).to receive(:invalid?).and_return(false)
    expect(rule).to receive(:save).and_return(true)
    expect(Flapjack::Data::Rule).to receive(:new).with(rule_data).
      and_return(rule)

    expect(rule).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(rule_data)

    post "/rules", Flapjack.dump_json(:rules => rule_data), jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json(:rules => rule_data.merge(:links => {
      :contact => nil,
      :media => [],
      :tags => []
    })))
  end

  it "does not create a rule if the data is improperly formatted" do
    expect(Flapjack::Data::Rule).to receive(:lock).with(Flapjack::Data::Contact,
      Flapjack::Data::Medium, Flapjack::Data::Tag, Flapjack::Data::Check,
      Flapjack::Data::Route).and_yield
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

    post "/rules", Flapjack.dump_json(:rules => rule_data), jsonapi_post_env
    expect(last_response.status).to eq(403)
  end

  it "creates a rule linked to a contact" do
    expect(Flapjack::Data::Rule).to receive(:lock).with(Flapjack::Data::Contact,
      Flapjack::Data::Medium, Flapjack::Data::Tag, Flapjack::Data::Check,
      Flapjack::Data::Route).and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    full_ids = double('full_ids')
    expect(full_ids).to receive(:associated_ids_for).with(:contact).and_return({rule.id => contact.id})
    expect(full_ids).to receive(:associated_ids_for).with(:media).and_return({rule.id => []})
    expect(full_ids).to receive(:associated_ids_for).with(:tags).and_return({rule.id => []})
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => [rule_data[:id]]).exactly(4).times.and_return(empty_ids, full_ids)

    expect(Flapjack::Data::Contact).to receive(:find_by_id!).with(contact_data[:id]).
      and_return(contact)

    expect(rule).to receive(:invalid?).and_return(false)
    expect(rule).to receive(:save).and_return(true)
    expect(rule).to receive(:contact=).with(contact)
    expect(Flapjack::Data::Rule).to receive(:new).with(rule_data).
      and_return(rule)

    expect(rule).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(rule_data)

    post "/rules", Flapjack.dump_json(:rules => rule_data.merge(:links => {:contact => contact.id})), jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json(:links => {
        'rules.contact' => 'http://example.org/contacts/{rules.contact}',
      },
      :rules => rule_data.merge(:links => {
        :contact => contact.id,
        :media => [],
        :tags => []
      }
    )))
  end

  it "does not create a rule with a linked contact if the contact doesn't exist" do
    expect(Flapjack::Data::Rule).to receive(:lock).with(Flapjack::Data::Contact,
      Flapjack::Data::Medium, Flapjack::Data::Tag, Flapjack::Data::Check,
      Flapjack::Data::Route).and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => [rule_data[:id]]).and_return(empty_ids)

    rule_with_contact_data = rule_data.merge(:links => {
      :contact => contact_data[:id]
    })

    expect(Flapjack::Data::Contact).to receive(:find_by_id!).with(contact_data[:id]).
      and_raise(Zermelo::Records::Errors::RecordNotFound.new(Flapjack::Data::Contact, contact_data[:id]))

    expect(rule).to receive(:invalid?).and_return(false)
    expect(rule).not_to receive(:save)
    expect(rule).not_to receive(:contact=).with(contact)
    expect(Flapjack::Data::Rule).to receive(:new).with(rule_data).
      and_return(rule)

    expect(Flapjack::Data::Rule).not_to receive(:as_jsonapi)

    post "/rules", Flapjack.dump_json(:rules => rule_with_contact_data), jsonapi_post_env
    expect(last_response.status).to eq(404)
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

    expect(Flapjack::Data::Rule).to receive(:count).and_return(1)

    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).
      and_return([rule])
    expect(Flapjack::Data::Rule).to receive(:sort).
      with(:id).and_return(sorted)

    full_ids = double('full_ids')
    expect(full_ids).to receive(:associated_ids_for).with(:contact).and_return({rule.id => nil})
    expect(full_ids).to receive(:associated_ids_for).with(:media).and_return({rule.id => []})
    expect(full_ids).to receive(:associated_ids_for).with(:tags).and_return({rule.id => []})
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => [rule.id]).exactly(3).times.and_return(full_ids)

    expect(rule).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(rule_data)

    get '/rules'
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:rules => [rule_data.merge(:links => {
      :contact => nil,
      :media => [],
      :tags => []
    })], :meta => meta))
  end

  it "gets a single rule" do
    expect(Flapjack::Data::Rule).to receive(:find_by_id!).
      with(rule.id).and_return(rule)

    full_ids = double('full_ids')
    expect(full_ids).to receive(:associated_ids_for).with(:contact).and_return({rule.id => nil})
    expect(full_ids).to receive(:associated_ids_for).with(:media).and_return({rule.id => []})
    expect(full_ids).to receive(:associated_ids_for).with(:tags).and_return({rule.id => []})
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => [rule.id]).exactly(3).times.and_return(full_ids)

    expect(rule).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(rule_data)

    get "/rules/#{rule.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:rules => rule_data.merge(:links => {
      :contact => nil,
      :media => [],
      :tags => []
    })))
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
    expect(rules).to receive(:associated_ids_for).with(:media).
      and_return(rule.id => [])
    expect(rules).to receive(:associated_ids_for).with(:tags).
      and_return(rule.id => [])
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => [rule.id]).exactly(4).times.and_return(rules)

    contacts = double('contacts')
    expect(contacts).to receive(:associated_ids_for).with(:media).and_return({contact.id => []})
    expect(contacts).to receive(:associated_ids_for).with(:rules).and_return({contact.id => [rule.id]})
    expect(Flapjack::Data::Contact).to receive(:intersect).
      with(:id => [contact_data[:id]]).twice.and_return(contacts)

    expect(Flapjack::Data::Contact).to receive(:find_by_ids!).
      with(contact.id).and_return([contact])

    expect(contact).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(contact_data)

    expect(rule).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(rule_data)

    get "/rules/#{rule.id}?include=contact"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:links => {
        'rules.contact' => 'http://example.org/contacts/{rules.contact}',
        'contacts.rules' => 'http://example.org/rules/{contacts.rules}',
      },
      :rules => rule_data.merge(:links => {
        :contact => contact.id,
        :media => [],
        :tags => []
      }),
      :linked => {
        :contacts => [contact_data.merge(:links => {
          :media => [],
          :rules => [rule.id]
        })]
      }
    ))
  end

  it "retrieves a rule and all its contact's media records" do
    expect(Flapjack::Data::Rule).to receive(:find_by_id!).
      with(rule.id).and_return(rule)

    rules = double('rules')
    expect(rules).to receive(:associated_ids_for).with(:contact).twice.
      and_return(rule.id => contact.id)
    expect(rules).to receive(:associated_ids_for).with(:media).
      and_return(rule.id => [medium.id])
    expect(rules).to receive(:associated_ids_for).with(:tags).
      and_return(rule.id => [])
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => [rule.id]).exactly(4).times.and_return(rules)

    contacts = double('contacts')
    expect(contacts).to receive(:associated_ids_for).with(:media).and_return({contact.id => [medium.id]})
    expect(Flapjack::Data::Contact).to receive(:intersect).
      with(:id => [contact_data[:id]]).and_return(contacts)

    medium_ids = double('medium_ids')
    expect(medium_ids).to receive(:associated_ids_for).with(:contact).and_return({medium.id => contact.id})
    expect(medium_ids).to receive(:associated_ids_for).with(:rules).and_return({medium.id => [rule.id]})
    expect(Flapjack::Data::Medium).to receive(:intersect).
      with(:id => [medium.id]).twice.and_return(medium_ids)

    expect(Flapjack::Data::Medium).to receive(:find_by_ids!).
      with(medium.id).and_return([medium])

    expect(medium).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(email_data)

    expect(rule).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(rule_data)

    get "/rules/#{rule.id}?include=contact.media"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:links => {
        'rules.contact' => 'http://example.org/contacts/{rules.contact}',
        'rules.media'   => 'http://example.org/media/{rules.media}',
        'media.contact' => 'http://example.org/contacts/{media.contact}',
        'media.rules'   => 'http://example.org/rules/{media.rules}',
      },
      :rules => rule_data.merge(:links => {
        :contact => contact.id,
        :media => [medium.id],
        :tags => []
      }),
      :linked => {
        :media => [email_data.merge(:links => {
          :contact => contact.id,
          :rules => [rule.id]
        })],
      }
    ))
  end

  it "retrieves a rule, its contact, and the contact's media records" do
    expect(Flapjack::Data::Rule).to receive(:find_by_id!).
      with(rule.id).and_return(rule)

    rules = double('rules')
    expect(rules).to receive(:associated_ids_for).with(:contact).twice.
      and_return(rule.id => contact.id)
    expect(rules).to receive(:associated_ids_for).with(:media).
      and_return(rule.id => [medium.id])
    expect(rules).to receive(:associated_ids_for).with(:tags).
      and_return(rule.id => [])
    expect(Flapjack::Data::Rule).to receive(:intersect).
      with(:id => [rule.id]).exactly(4).times.and_return(rules)

    contacts = double('contacts')
    expect(contacts).to receive(:associated_ids_for).with(:media).twice.
      and_return({contact.id => [medium.id]})
    expect(contacts).to receive(:associated_ids_for).with(:rules).and_return({contact.id => [rule.id]})
    expect(Flapjack::Data::Contact).to receive(:intersect).
      with(:id => [contact_data[:id]]).exactly(3).times.and_return(contacts)

    expect(Flapjack::Data::Contact).to receive(:find_by_ids!).
      with(contact.id).and_return([contact])

    media = double('media')
    expect(media).to receive(:associated_ids_for).with(:contact).and_return({medium.id => contact.id})
    expect(media).to receive(:associated_ids_for).with(:rules).and_return({medium.id => [rule.id]})
    expect(Flapjack::Data::Medium).to receive(:intersect).
      with(:id => [medium.id]).twice.and_return(media)

    expect(Flapjack::Data::Medium).to receive(:find_by_ids!).
      with(medium.id).and_return([medium])

    expect(contact).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(contact_data)

    expect(medium).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(email_data)

    expect(rule).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(rule_data)

    get "/rules/#{rule.id}?include=contact,contact.media"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:links => {
        'rules.contact'  => 'http://example.org/contacts/{rules.contact}',
        'rules.media'    => 'http://example.org/media/{rules.media}',
        'contacts.media' => 'http://example.org/media/{contacts.media}',
        'contacts.rules' => 'http://example.org/rules/{contacts.rules}',
        'media.contact'  => 'http://example.org/contacts/{media.contact}',
        'media.rules'    => 'http://example.org/rules/{media.rules}',
      },
      :rules => rule_data.merge(:links => {
        :contact => contact.id,
        :media => [medium.id],
        :tags => []
      }),
      :linked => {
        :contacts => [contact_data.merge(:links => {
          :media => [medium.id],
          :rules => [rule.id],
        })],
        :media => [email_data.merge(:links => {
          :contact => contact.id,
          :rules => [rule.id]
        })]
      }
    ))
  end

  it "sets a contact for a rule" do
    expect(Flapjack::Data::Rule).to receive(:find_by_ids!).
      with(rule.id).and_return([rule])

    expect(Flapjack::Data::Contact).to receive(:find_by_id!).with(contact_data[:id]).
      and_return(contact)

    expect(rule).to receive(:invalid?).and_return(false)
    expect(rule).to receive(:save).and_return(true)

    expect(rule).to receive(:contact=).with(contact)

    put "/rules/#{rule.id}",
      Flapjack.dump_json(:rules =>
        {:id => rule.id, :links => {:contact => contact.id}}
      ),
      jsonapi_put_env
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

    put "/rules/#{rule.id},#{rule_2.id}",
      Flapjack.dump_json(:rules => [
        {:id => rule.id, :links => {:contact => contact.id}},
        {:id => rule_2.id, :links => {:contact => contact.id}}
      ]),
      jsonapi_put_env
    expect(last_response.status).to eq(204)
  end

  it "does not set a contact for a notification rule that does not exist" do
    expect(Flapjack::Data::Rule).to receive(:find_by_ids!).
      with(rule.id).
      and_raise(Zermelo::Records::Errors::RecordsNotFound.new(Flapjack::Data::Rule, [rule.id]))

    put "/rules/#{rule.id}",
      Flapjack.dump_json(:rules =>
        {:id => rule.id, :links => {:contact => contact.id}}
      ),
      jsonapi_put_env
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
