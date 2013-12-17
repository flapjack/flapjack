require 'spec_helper'
require 'flapjack/gateways/api'

describe 'Flapjack::Gateways::API::ContactMethods', :sinatra => true, :logger => true do

  def app
    Flapjack::Gateways::API
  end

  let(:json_data)       { {'valid' => 'json'} }

  let(:contact)      { double(Flapjack::Data::Contact) }
  let(:all_contacts) { double('all_contacts', :all => [contact]) }
  let(:no_contacts)  { double('no_contacts', :all => []) }

  let(:media) {
    {'email' => 'ada@example.com',
     'sms'   => '04123456789'
    }
  }

  let(:media_intervals) {
    {'email' => 500,
     'sms'   => 300
    }
  }

  let(:redis)           { double(::Redis) }

  let(:notification_rule) {
    double(Flapjack::Data::NotificationRule, :id => '1', :contact_id => '21')
  }

  let(:notification_rule_data) {
    {"contact_id"         => "21",
     "tags"               => ["database","physical"],
     "entities"           => ["foo-app-01.example.com"],
     "time_restrictions"  => nil,
     "unknown_media"      => ["jabber"],
     "warning_media"      => ["email"],
     "critical_media"     => ["sms", "email"],
     "unknown_blackhole"  => false,
     "warning_blackhole"  => false,
     "critical_blackhole" => false
    }
  }

  before(:all) do
    Flapjack::Gateways::API.class_eval {
      set :raise_errors, true
    }
  end

  before(:each) do
    allow(Flapjack).to receive(:redis).and_return(redis)
    Flapjack::Gateways::API.instance_variable_set('@config', {})
    Flapjack::Gateways::API.instance_variable_set('@logger', @logger)
    Flapjack::Gateways::API.start
  end

  it "creates contacts from a submitted list" do
    contacts = {'contacts' =>
      [{"id" => "0362",
        "first_name" => "John",
        "last_name" => "Smith",
        "email" => "johns@example.dom",
        "media" => {"email"  => "johns@example.dom",
                    "jabber" => "johns@conference.localhost"}},
       {"id" => "0363",
        "first_name" => "Jane",
        "last_name" => "Jones",
        "email" => "jane@example.dom",
        "media" => {"email" => "jane@example.dom"}}
      ]
    }

    media = double('media')
    media_2 = double('media_2')

    medium = double(Flapjack::Data::Medium)
    medium_2 = double(Flapjack::Data::Medium)
    medium_3 = double(Flapjack::Data::Medium)

    expect(medium).to receive(:address=).with('johns@example.dom')
    expect(medium_2).to receive(:address=).with('johns@conference.localhost')
    expect(medium_3).to receive(:address=).with('jane@example.dom')

    expect(medium).to receive(:save).and_return(true)
    expect(medium_2).to receive(:save).and_return(true)
    expect(medium_3).to receive(:save).and_return(true)

    expect(media).to receive(:each)
    expect(media_2).to receive(:each)

    expect(media).to receive(:<<).with(medium)
    expect(media).to receive(:<<).with(medium_2)
    expect(media_2).to receive(:<<).with(medium_3)

    expect(Flapjack::Data::Medium).to receive(:new).with(:type => 'email').and_return(medium)
    expect(Flapjack::Data::Medium).to receive(:new).with(:type => 'jabber').and_return(medium_2)
    expect(Flapjack::Data::Medium).to receive(:new).with(:type => 'email').and_return(medium_3)

    contact_2 = double(Flapjack::Data::Contact)
    pd_cred = double('pagerduty_credentials')
    expect(pd_cred).to receive(:clear)
    pd_cred_2 = double('pagerduty_credentials_2')
    expect(pd_cred_2).to receive(:clear)

    expect(contact).to receive(:pagerduty_credentials).and_return(pd_cred)
    expect(contact).to receive(:first_name=).with('John')
    expect(contact).to receive(:last_name=).with('Smith')
    expect(contact).to receive(:email=).with('johns@example.dom')

    expect(contact_2).to receive(:pagerduty_credentials).and_return(pd_cred_2)
    expect(contact_2).to receive(:first_name=).with('Jane')
    expect(contact_2).to receive(:last_name=).with('Jones')
    expect(contact_2).to receive(:email=).with('jane@example.dom')

    expect(contact).to receive(:media).exactly(3).times.and_return(media)
    expect(contact_2).to receive(:media).twice.and_return(media_2)

    expect(contact).to receive(:save).and_return(true)
    expect(contact_2).to receive(:save).and_return(true)

    expect(Flapjack::Data::Contact).to receive(:all).and_return([])
    expect(Flapjack::Data::Contact).to receive(:new).with(:id => "0362").and_return(contact)
    expect(Flapjack::Data::Contact).to receive(:new).with(:id => "0363").and_return(contact_2)

    post "/contacts", contacts.to_json, {'CONTENT_TYPE' => 'application/json'}
    expect(last_response.status).to eq(204)
  end

  it "does not create contacts if the data is improperly formatted" do
    expect(Flapjack::Data::Contact).not_to receive(:add)

    post "/contacts", {'contacts' => ["Hello", "again"]}.to_json,
      {'CONTENT_TYPE' => 'application/json'}
    expect(last_response.status).to eq(403)
  end

  it "updates a contact if it is already present" do
    contacts = {'contacts' =>
      [{"id" => "0363",
        "first_name" => "Jane",
        "last_name" => "Jones",
        "email" => "jane@example.dom",
        "media" => {"email" => "jane@example.dom"}}
      ]
    }

    media = double('media')

    medium = double(Flapjack::Data::Medium)
    expect(medium).to receive(:address=).with('jane@example.dom')
    expect(medium).to receive(:save).and_return(true)
    expect(Flapjack::Data::Medium).to receive(:new).with(:type => 'email').and_return(medium)

    expect(media).to receive(:each)

    expect(media).to receive(:<<).with(medium)

    existing = double(Flapjack::Data::Contact)
    expect(existing).to receive(:id).and_return("0363")

    pd_cred = double('pagerduty_credentials')
    expect(pd_cred).to receive(:clear)

    expect(existing).to receive(:pagerduty_credentials).and_return(pd_cred)
    expect(existing).to receive(:first_name=).with('Jane')
    expect(existing).to receive(:last_name=).with('Jones')
    expect(existing).to receive(:email=).with('jane@example.dom')

    expect(existing).to receive(:media).twice.and_return(media)

    expect(existing).to receive(:save).and_return(true)

    expect(Flapjack::Data::Contact).to receive(:all).and_return([existing])

    post "/contacts", contacts.to_json, {'CONTENT_TYPE' => 'application/json'}
    expect(last_response.status).to eq(204)
  end

  it "deletes a contact not found in a bulk update list" do
    contacts = {'contacts' =>
      [{"id" => "0363",
        "first_name" => "Jane",
        "last_name" => "Jones",
        "email" => "jane@example.dom",
        "media" => {"email" => "jane@example.dom"}}
      ]
    }

    existing = double(Flapjack::Data::Contact)
    expect(existing).to receive(:id).twice.and_return("0362")
    expect(existing).to receive(:destroy)

    expect(Flapjack::Data::Contact).to receive(:all).and_return([existing])

    medium = double(Flapjack::Data::Medium)
    expect(medium).to receive(:address=).with('jane@example.dom')
    expect(medium).to receive(:save).and_return(true)
    expect(Flapjack::Data::Medium).to receive(:new).with(:type => 'email').and_return(medium)

    media = double('media')
    expect(media).to receive(:each)
    expect(media).to receive(:<<).with(medium)

    pd_cred = double('pagerduty_credentials')
    expect(pd_cred).to receive(:clear)

    expect(contact).to receive(:pagerduty_credentials).and_return(pd_cred)
    expect(contact).to receive(:first_name=).with('Jane')
    expect(contact).to receive(:last_name=).with('Jones')
    expect(contact).to receive(:email=).with('jane@example.dom')
    expect(contact).to receive(:media).twice.and_return(media)
    expect(contact).to receive(:save).and_return(true)

    expect(Flapjack::Data::Contact).to receive(:new).with(:id => "0363").and_return(contact)

    post "/contacts", contacts.to_json, {'CONTENT_TYPE' => 'application/json'}
    expect(last_response.status).to eq(204)
  end

  it "returns all the contacts" do
    expect(contact).to receive(:as_json).and_return(json_data)
    expect(Flapjack::Data::Contact).to receive(:all).and_return([contact])

    get '/contacts'
    expect(last_response).to be_ok
    expect(last_response.body).to eq([json_data].to_json)
  end

  it "returns the core information of a specified contact" do
    expect(contact).to receive(:as_json).and_return(json_data)
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(contact)

    get "/contacts/0362"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(json_data.to_json)
  end

  it "does not return information for a contact that does not exist" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(nil)

    get "/contacts/0362"
    expect(last_response).to be_forbidden
  end

  it "lists a contact's notification rules" do
    notification_rule_2 = double(Flapjack::Data::NotificationRule)
    expect(notification_rule).to receive(:as_json).and_return(json_data)
    expect(notification_rule_2).to receive(:as_json).and_return(json_data)

    all_notification_rules = double('all_notification_rules',
      :all =>  [ notification_rule, notification_rule_2 ])

    expect(contact).to receive(:notification_rules).and_return(all_notification_rules)
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(contact)

    get "/contacts/0362/notification_rules"
    expect(last_response).to be_ok
    expect(last_response.body).to eq([json_data, json_data].to_json)
  end

  it "does not list notification rules for a contact that does not exist" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(nil)

    get "/contacts/0362/notification_rules"
    expect(last_response).to be_forbidden
  end

  it "returns a specified notification rule" do
    expect(notification_rule).to receive(:as_json).and_return(json_data)
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_id).
      with('abcdef').and_return(notification_rule)

    get "/notification_rules/abcdef"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(json_data.to_json)
  end

  it "does not return a notification rule that does not exist" do
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_id).
      with('abcdef').and_return(nil)

    get "/notification_rules/abcdef"
    expect(last_response).to be_forbidden
  end

  # POST /notification_rules
  it "creates a new notification rule" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(notification_rule_data['contact_id']).and_return(contact)

    # symbolize the keys
    notification_rule_data_sym = notification_rule_data.inject({}){|memo,(k,v)|
      memo[k.to_sym] = v; memo
    }
    notification_rule_data_sym.delete(:contact_id)
    notification_rule_data_sym[:tags] = Set.new(notification_rule_data['tags'])
    expect(notification_rule).to receive(:as_json).and_return(json_data)
    expect(notification_rule).to receive(:save).and_return(true)
    expect(Flapjack::Data::NotificationRule).to receive(:new).
      with(notification_rule_data_sym).and_return(notification_rule)

    notification_rules = double('notification_rules')
    expect(notification_rules).to receive(:<<).with(notification_rule)
    expect(contact).to receive(:notification_rules).and_return(notification_rules)

    post "/notification_rules", notification_rule_data.to_json,
      {'CONTENT_TYPE' => 'application/json'}
    expect(last_response).to be_ok
    expect(last_response.body).to eq(json_data.to_json)
  end

  it "does not create a notification_rule for a contact that's not present" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(notification_rule_data['contact_id']).and_return(nil)

    post "/notification_rules", notification_rule_data.to_json,
      {'CONTENT_TYPE' => 'application/json'}
    expect(last_response).to be_forbidden
  end

  it "does not create a notification_rule if a rule id is provided" do
    post "/notification_rules", notification_rule_data.merge(:id => '1').to_json,
      {'CONTENT_TYPE' => 'application/json'}
    expect(last_response.status).to eq(403)
  end

  # PUT /notification_rules/RULE_ID
  it "updates a notification rule" do
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_id).
      with(notification_rule.id).and_return(notification_rule)

    # symbolize the keys
    notification_rule_data_sym = notification_rule_data.inject({}){|memo,(k,v)|
      memo[k.to_sym] = v; memo
    }
    notification_rule_data_sym.delete(:contact_id)
    notification_rule_data_sym[:tags] = Set.new(notification_rule_data['tags'])
    notification_rule_data_sym.each_pair do |k,v|
      expect(notification_rule).to receive("#{k}=".to_sym).with(v)
    end
    expect(notification_rule).to receive(:save).and_return(true)
    expect(notification_rule).to receive(:as_json).and_return(json_data)

    put "/notification_rules/#{notification_rule.id}", notification_rule_data.to_json,
      {'CONTENT_TYPE' => 'application/json'}
    expect(last_response).to be_ok
    expect(last_response.body).to eq(json_data.to_json)
  end

  it "does not update a notification rule that's not present" do
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_id).
      with(notification_rule.id).and_return(nil)

    put "/notification_rules/#{notification_rule.id}", notification_rule_data
    expect(last_response).to be_forbidden
  end

  # DELETE /notification_rules/RULE_ID
  it "deletes a notification rule" do
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_id).
      with(notification_rule.id).and_return(notification_rule)

    expect(notification_rule).to receive(:contact).and_return(contact)

    expect(notification_rule).to receive(:destroy)
    notification_rules = double('notification_rules')
    expect(notification_rules).to receive(:delete).with(notification_rule)
    expect(contact).to receive(:notification_rules).and_return(notification_rules)

    delete "/notification_rules/#{notification_rule.id}"
    expect(last_response.status).to eq(204)
  end

  it "does not delete a notification rule that's not present" do
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_id).
      with(notification_rule.id).and_return(nil)

    delete "/notification_rules/#{notification_rule.id}"
    expect(last_response).to be_forbidden
  end

  it "does not delete a notification rule if the contact is not present" do
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_id).
      with(notification_rule.id).and_return(notification_rule)

    expect(notification_rule).to receive(:contact).and_return(nil)

    delete "/notification_rules/#{notification_rule.id}"
    expect(last_response).to be_forbidden
  end

  # GET /contacts/CONTACT_ID/media
  it "returns the media of a contact" do
    expect(contact).to receive(:media).and_return([json_data])
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(contact)

    get "/contacts/0362/media"
    expect(last_response).to be_ok
    expect(last_response.body).to eq([json_data].to_json)
  end

  it "does not return the media of a contact if the contact is not present" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(nil)

    get "/contacts/0362/media"
    expect(last_response).to be_forbidden
  end

  # GET /contacts/CONTACT_ID/media/MEDIA
  it "returns the specified media of a contact" do
    medium = double(Flapjack::Data::Medium)
    expect(medium).to receive(:as_json).and_return(json_data)
    all_media = double('all_media', :all => [medium])
    media = double('media')
    expect(media).to receive(:intersect).with(:type => 'sms').and_return(all_media)
    expect(contact).to receive(:media).and_return(media)

    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(contact)

    get "/contacts/0362/media/sms"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(json_data.to_json)
  end

  it "does not return the media of a contact if the contact is not present" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(nil)

    get "/contacts/0362/media/sms"
    expect(last_response).to be_forbidden
  end

  it "does not return the media of a contact if the media is not present" do
    all_media = double('all_media', :all => [])
    media = double('media')
    expect(media).to receive(:intersect).with(:type => 'telepathy').and_return(all_media)
    expect(contact).to receive(:media).and_return(media)

    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(contact)

    get "/contacts/0362/media/telepathy"
    expect(last_response).to be_forbidden
  end

  # PUT, DELETE /contacts/CONTACT_ID/media/MEDIA
  it "creates/updates a media of a contact" do
    medium = double(Flapjack::Data::Medium)
    expect(medium).to receive(:address=).with('04987654321')
    expect(medium).to receive(:interval=).with(200)
    expect(medium).to receive(:save).and_return(true)
    expect(medium).to receive(:as_json).and_return(json_data)

    all_media = double('all_media', :all => [medium])

    media = double('media')
    expect(media).to receive(:intersect).with(:type => 'sms').and_return(all_media)
    expect(contact).to receive(:media).and_return(media)

    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(contact)

    put "/contacts/0362/media/sms", {:address => '04987654321', :interval => '200'}
    expect(last_response).to be_ok
    expect(last_response.body).to eq(json_data.to_json)
  end

  it "does not create a media of a contact that's not present" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(nil)

    put "/contacts/0362/media/sms", {:address => '04987654321', :interval => '200'}
    expect(last_response).to be_forbidden
  end

  it "does not create a media of a contact if no address is provided" do
    medium = double(Flapjack::Data::Medium)
    expect(medium).to receive(:address=).with(nil)
    expect(medium).to receive(:interval=).with(200)
    expect(medium).to receive(:save).and_return(false)
    errors = double('errors', :full_messages => ['Address cannot be blank'])
    expect(medium).to receive(:errors).and_return(errors)

    all_media = double('all_media', :all => [medium])

    media = double('media')
    expect(media).to receive(:intersect).with(:type => 'sms').and_return(all_media)
    expect(contact).to receive(:media).and_return(media)

    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(contact)

    put "/contacts/0362/media/sms", {:interval => '200'}
    expect(last_response).to be_forbidden
  end

  it "creates a media of a contact even if no interval is provided" do
    medium = double(Flapjack::Data::Medium)
    expect(medium).to receive(:address=).with('04987654321')
    expect(medium).to receive(:save).and_return(true)
    expect(medium).to receive(:as_json).and_return(json_data)
    expect(Flapjack::Data::Medium).to receive(:new).and_return(medium)

    no_media = double('no_media', :all => [])

    media = double('media')
    expect(media).to receive(:intersect).with(:type => 'sms').and_return(no_media)
    expect(media).to receive(:<<).with(medium)
    expect(contact).to receive(:media).and_return(media)

    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(contact)

    put "/contacts/0362/media/sms", {:address => '04987654321'}
    expect(last_response).to be_ok
  end

  it "deletes a media of a contact" do
    medium = double(Flapjack::Data::Medium)
    expect(medium).to receive(:destroy)

    all_media = double('all_media', :all => [medium])

    media = double('media')
    expect(media).to receive(:intersect).with(:type => 'sms').and_return(all_media)
    expect(media).to receive(:delete).with(medium)

    expect(contact).to receive(:media).and_return(media)
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(contact)

    delete "/contacts/0362/media/sms"
    expect(last_response.status).to eq(204)
  end

  it "does not delete a media of a contact that's not present" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(nil)

    delete "/contacts/0362/media/sms"
    expect(last_response).to be_forbidden
  end

  # GET /contacts/CONTACT_ID/timezone
  it "returns the timezone of a contact" do
    expect(contact).to receive(:timezone).and_return(::ActiveSupport::TimeZone.new('Australia/Sydney'))
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(contact)

    get "/contacts/0362/timezone"
    expect(last_response).to be_ok
    expect(last_response.body).to eq('"Australia/Sydney"')
  end

  it "doesn't get the timezone of a contact that doesn't exist" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(nil)

    get "/contacts/0362/timezone"
    expect(last_response).to be_forbidden
  end

  # PUT /contacts/CONTACT_ID/timezone
  it "sets the timezone of a contact" do
    expect(contact).to receive(:timezone=).with('Australia/Perth')
    expect(contact).to receive(:save).and_return(true)
    expect(contact).to receive(:timezone).and_return(ActiveSupport::TimeZone.new('Australia/Perth'))
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(contact)

    put "/contacts/0362/timezone", {:timezone => 'Australia/Perth'}
    expect(last_response).to be_ok
  end

  it "doesn't set the timezone of a contact who can't be found" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(nil)

    put "/contacts/0362/timezone", {:timezone => 'Australia/Perth'}
    expect(last_response).to be_forbidden
  end

  # DELETE /contacts/CONTACT_ID/timezone
  it "deletes the timezone of a contact" do
    expect(contact).to receive(:timezone=).with(nil)
    expect(contact).to receive(:save).and_return(true)
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(contact)

    delete "/contacts/0362/timezone"
    expect(last_response.status).to eq(204)
  end

  it "does not delete the timezone of a contact that's not present" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(nil)

    delete "/contacts/0362/timezone"
    expect(last_response).to be_forbidden
  end

  it "sets a single tag on a contact and returns current tags" do
    tags = ['web']
    expect(contact).to receive(:tags=).with(Set.new(tags))
    expect(contact).to receive(:tags).twice.and_return(Set.new, Set.new(tags))
    expect(contact).to receive(:save).and_return(true)
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(contact)

    post "contacts/0362/tags", :tag => tags.first
    expect(last_response).to be_ok
    expect(last_response.body).to eq( tags.to_json )
  end

  it "does not set a single tag on a contact that's not found" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(nil)

    post "contacts/0362/tags", :tag => 'web'
    expect(last_response).to be_forbidden
  end

  it "sets multiple tags on a contact and returns current tags" do
    tags = ['web', 'app']
    expect(contact).to receive(:tags=).with(Set.new(tags))
    expect(contact).to receive(:tags).twice.and_return(Set.new, Set.new(tags))
    expect(contact).to receive(:save).and_return(true)
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(contact)

    # NB submitted at a lower level as tag[]=web&tag[]=app
    post "contacts/0362/tags", :tag => tags
    expect(last_response).to be_ok
    expect(last_response.body).to eq( tags.to_json )
  end

  it "does not set multiple tags on a contact that's not found" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(nil)

    post "contacts/0362/tags", :tag => ['web', 'app']
    expect(last_response).to be_forbidden
  end

  it "removes a single tag from a contact" do
    tags = ['web']
    expect(contact).to receive(:tags=).with(Set.new)
    expect(contact).to receive(:tags).and_return(Set.new(tags))
    expect(contact).to receive(:save).and_return(true)
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(contact)

    delete "contacts/0362/tags", :tag => tags.first
    expect(last_response.status).to eq(204)
  end

  it "does not remove a single tag from a contact that's not found" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(nil)

    delete "contacts/0362/tags", :tag => 'web'
    expect(last_response).to be_forbidden
  end

  it "removes multiple tags from a contact" do
    tags = ['web', 'app']
    expect(contact).to receive(:tags=).with(Set.new)
    expect(contact).to receive(:tags).and_return(Set.new(tags))
    expect(contact).to receive(:save).and_return(true)
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(contact)

    delete "contacts/0362/tags", :tag => tags
    expect(last_response.status).to eq(204)
  end

  it "does not remove multiple tags from a contact that's not found" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(nil)

    delete "contacts/0362/tags", :tag => ['web', 'app']
    expect(last_response).to be_forbidden
  end

  it "gets all tags on a contact" do
    expect(contact).to receive(:tags).and_return(Set.new(['web', 'app']))
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(contact)

    get "contacts/0362/tags"
    expect(last_response).to be_ok
    expect(last_response.body).to eq( ['web', 'app'].to_json )
  end

  it "does not get all tags on a contact that's not found" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(nil)

    get "contacts/0362/tags"
    expect(last_response).to be_forbidden
  end

  it "gets all entity tags for a contact" do
    entity_1 = double(Flapjack::Data::Entity)
    expect(entity_1).to receive(:name).and_return('entity_1')
    expect(entity_1).to receive(:tags).and_return(Set.new(['web']))
    entity_2 = double(Flapjack::Data::Entity)
    expect(entity_2).to receive(:name).and_return('entity_2')
    expect(entity_2).to receive(:tags).and_return(Set.new(['app']))

    all_entities = double('all_entities', :all => [entity_1, entity_2])
    expect(contact).to receive(:entities).and_return(all_entities)

    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(contact)

    get "contacts/0362/entity_tags"
    expect(last_response).to be_ok
    tag_response = {'entity_1' => ['web'],
                    'entity_2' => ['app']}
    expect(last_response.body).to eq( tag_response.to_json )
  end

  it "does not get all entity tags for a contact that's not found" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(nil)

    get "contacts/0362/entity_tags"
    expect(last_response).to be_forbidden
  end

  it "adds tags to multiple entities for a contact" do
    tags_1 = Set.new
    tags_2 = Set.new

    entity_1 = double(Flapjack::Data::Entity)
    expect(entity_1).to receive(:name).twice.and_return('entity_1')
    expect(entity_1).to receive(:tags).twice.and_return(tags_1, tags_1 + ['web'])
    expect(entity_1).to receive(:tags=).with(tags_1 + ['web'])
    entity_2 = double(Flapjack::Data::Entity)
    expect(entity_2).to receive(:name).twice.and_return('entity_2')
    expect(entity_2).to receive(:tags).twice.and_return(tags_2, tags_2 + ['app'])
    expect(entity_2).to receive(:tags=).with(tags_2 + ['app'])

    all_entities = double('all_entities')
    expect(all_entities).to receive(:all).and_return([entity_1, entity_2])
    expect(all_entities).to receive(:each).and_yield(entity_1).and_yield(entity_2)

    expect(contact).to receive(:entities).and_return(all_entities)

    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(contact)

    post "contacts/0362/entity_tags",
      :entity => {'entity_1' => ['web'], 'entity_2' => ['app']}
    expect(last_response).to be_ok
    tag_response = {'entity_1' => ['web'],
                    'entity_2' => ['app']}
    expect(last_response.body).to eq( tag_response.to_json )
  end

  it "does not add tags to multiple entities for a contact that's not found" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(nil)

    post "contacts/0362/entity_tags",
      :entity => {'entity_1' => ['web'], 'entity_2' => ['app']}
    expect(last_response).to be_forbidden
  end

  it "deletes tags from multiple entities for a contact" do
    tags_1 = Set.new(['web'])
    tags_2 = Set.new(['app'])

    entity_1 = double(Flapjack::Data::Entity)
    expect(entity_1).to receive(:name).and_return('entity_1')
    expect(entity_1).to receive(:tags).and_return(tags_1)
    expect(entity_1).to receive(:tags=).with(tags_1 - ['web'])
    entity_2 = double(Flapjack::Data::Entity)
    expect(entity_2).to receive(:name).and_return('entity_2')
    expect(entity_2).to receive(:tags).and_return(tags_2)
    expect(entity_2).to receive(:tags=).with(tags_2 - ['app'])

    all_entities = double('all_entities')
    expect(all_entities).to receive(:each).and_yield(entity_1).and_yield(entity_2)

    expect(contact).to receive(:entities).and_return(all_entities)

    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(contact)

    delete "contacts/0362/entity_tags",
      :entity => {'entity_1' => ['web'], 'entity_2' => ['app']}
    expect(last_response.status).to eq(204)
  end

  it "does not delete tags from multiple entities for a contact that's not found" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with('0362').and_return(nil)

    delete "contacts/0362/entity_tags",
      :entity => {'entity_1' => ['web'], 'entity_2' => ['app']}
    expect(last_response).to be_forbidden
  end

end
