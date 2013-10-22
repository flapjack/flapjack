require 'spec_helper'
require 'flapjack/gateways/api'

describe 'Flapjack::Gateways::API::ContactMethods', :sinatra => true, :logger => true, :json => true do

  def app
    Flapjack::Gateways::API
  end

  let(:json_data)       { {'valid' => 'json'} }

  let(:contact)      { mock(Flapjack::Data::ContactR) }
  let(:all_contacts) { mock('all_contacts', :all => [contact]) }
  let(:no_contacts)  { mock('no_contacts', :all => []) }

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

  let(:redis)           { mock(::Redis) }

  let(:notification_rule) {
    mock(Flapjack::Data::NotificationRuleR, :id => '1', :contact_id => '21')
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
    Flapjack.stub(:redis).and_return(redis)
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

    media = mock('media')
    media_2 = mock('media_2')

    medium = mock(Flapjack::Data::MediumR)
    medium_2 = mock(Flapjack::Data::MediumR)
    medium_3 = mock(Flapjack::Data::MediumR)

    medium.should_receive(:address=).with('johns@example.dom')
    medium_2.should_receive(:address=).with('johns@conference.localhost')
    medium_3.should_receive(:address=).with('jane@example.dom')

    medium.should_receive(:save).and_return(true)
    medium_2.should_receive(:save).and_return(true)
    medium_3.should_receive(:save).and_return(true)

    media.should_receive(:each)
    media_2.should_receive(:each)

    media.should_receive(:<<).with(medium)
    media.should_receive(:<<).with(medium_2)
    media_2.should_receive(:<<).with(medium_3)

    Flapjack::Data::MediumR.should_receive(:new).with(:type => 'email').and_return(medium)
    Flapjack::Data::MediumR.should_receive(:new).with(:type => 'jabber').and_return(medium_2)
    Flapjack::Data::MediumR.should_receive(:new).with(:type => 'email').and_return(medium_3)

    contact_2 = mock(Flapjack::Data::ContactR)
    pd_cred = mock('pagerduty_credentials')
    pd_cred.should_receive(:clear)
    pd_cred_2 = mock('pagerduty_credentials_2')
    pd_cred_2.should_receive(:clear)

    contact.should_receive(:pagerduty_credentials).and_return(pd_cred)
    contact.should_receive(:first_name=).with('John')
    contact.should_receive(:last_name=).with('Smith')
    contact.should_receive(:email=).with('johns@example.dom')

    contact_2.should_receive(:pagerduty_credentials).and_return(pd_cred_2)
    contact_2.should_receive(:first_name=).with('Jane')
    contact_2.should_receive(:last_name=).with('Jones')
    contact_2.should_receive(:email=).with('jane@example.dom')

    contact.should_receive(:media).exactly(3).times.and_return(media)
    contact_2.should_receive(:media).twice.and_return(media_2)

    contact.should_receive(:save).and_return(true)
    contact_2.should_receive(:save).and_return(true)

    Flapjack::Data::ContactR.should_receive(:all).and_return([])
    Flapjack::Data::ContactR.should_receive(:new).with(:id => "0362").and_return(contact)
    Flapjack::Data::ContactR.should_receive(:new).with(:id => "0363").and_return(contact_2)

    post "/contacts", contacts.to_json, {'CONTENT_TYPE' => 'application/json'}
    last_response.status.should == 204
  end

  it "does not create contacts if the data is improperly formatted" do
    Flapjack::Data::ContactR.should_not_receive(:add)

    post "/contacts", {'contacts' => ["Hello", "again"]}.to_json,
      {'CONTENT_TYPE' => 'application/json'}
    last_response.status.should == 403
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

    media = mock('media')

    medium = mock(Flapjack::Data::MediumR)
    medium.should_receive(:address=).with('jane@example.dom')
    medium.should_receive(:save).and_return(true)
    Flapjack::Data::MediumR.should_receive(:new).with(:type => 'email').and_return(medium)

    media.should_receive(:each)

    media.should_receive(:<<).with(medium)

    existing = mock(Flapjack::Data::ContactR)
    existing.should_receive(:id).and_return("0363")

    pd_cred = mock('pagerduty_credentials')
    pd_cred.should_receive(:clear)

    existing.should_receive(:pagerduty_credentials).and_return(pd_cred)
    existing.should_receive(:first_name=).with('Jane')
    existing.should_receive(:last_name=).with('Jones')
    existing.should_receive(:email=).with('jane@example.dom')

    existing.should_receive(:media).twice.and_return(media)

    existing.should_receive(:save).and_return(true)

    Flapjack::Data::ContactR.should_receive(:all).and_return([existing])

    post "/contacts", contacts.to_json, {'CONTENT_TYPE' => 'application/json'}
    last_response.status.should == 204
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

    existing = mock(Flapjack::Data::ContactR)
    existing.should_receive(:id).twice.and_return("0362")
    existing.should_receive(:destroy)

    Flapjack::Data::ContactR.should_receive(:all).and_return([existing])

    medium = mock(Flapjack::Data::MediumR)
    medium.should_receive(:address=).with('jane@example.dom')
    medium.should_receive(:save).and_return(true)
    Flapjack::Data::MediumR.should_receive(:new).with(:type => 'email').and_return(medium)

    media = mock('media')
    media.should_receive(:each)
    media.should_receive(:<<).with(medium)

    pd_cred = mock('pagerduty_credentials')
    pd_cred.should_receive(:clear)

    contact.should_receive(:pagerduty_credentials).and_return(pd_cred)
    contact.should_receive(:first_name=).with('Jane')
    contact.should_receive(:last_name=).with('Jones')
    contact.should_receive(:email=).with('jane@example.dom')
    contact.should_receive(:media).twice.and_return(media)
    contact.should_receive(:save).and_return(true)

    Flapjack::Data::ContactR.should_receive(:new).with(:id => "0363").and_return(contact)

    post "/contacts", contacts.to_json, {'CONTENT_TYPE' => 'application/json'}
    last_response.status.should == 204
  end

  it "returns all the contacts" do
    contact.should_receive(:as_json).and_return(json_data)
    Flapjack::Data::ContactR.should_receive(:all).and_return([contact])

    get '/contacts'
    last_response.should be_ok
    last_response.body.should == [json_data].to_json
  end

  it "returns the core information of a specified contact" do
    contact.should_receive(:as_json).and_return(json_data)
    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(contact)

    get "/contacts/0362"
    last_response.should be_ok
    last_response.body.should == json_data.to_json
  end

  it "does not return information for a contact that does not exist" do
    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(nil)

    get "/contacts/0362"
    last_response.should be_forbidden
  end

  it "lists a contact's notification rules" do
    notification_rule_2 = mock(Flapjack::Data::NotificationRuleR)
    notification_rule.should_receive(:as_json).and_return(json_data)
    notification_rule_2.should_receive(:as_json).and_return(json_data)

    all_notification_rules = mock('all_notification_rules',
      :all =>  [ notification_rule, notification_rule_2 ])

    contact.should_receive(:notification_rules).and_return(all_notification_rules)
    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(contact)

    get "/contacts/0362/notification_rules"
    last_response.should be_ok
    last_response.body.should == [json_data, json_data].to_json
  end

  it "does not list notification rules for a contact that does not exist" do
    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(nil)

    get "/contacts/0362/notification_rules"
    last_response.should be_forbidden
  end

  it "returns a specified notification rule" do
    notification_rule.should_receive(:as_json).and_return(json_data)
    Flapjack::Data::NotificationRuleR.should_receive(:find_by_id).
      with('abcdef').and_return(notification_rule)

    get "/notification_rules/abcdef"
    last_response.should be_ok
    last_response.body.should == json_data.to_json
  end

  it "does not return a notification rule that does not exist" do
    Flapjack::Data::NotificationRuleR.should_receive(:find_by_id).
      with('abcdef').and_return(nil)

    get "/notification_rules/abcdef"
    last_response.should be_forbidden
  end

  # POST /notification_rules
  it "creates a new notification rule" do
    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with(notification_rule_data['contact_id']).and_return(contact)

    # symbolize the keys
    notification_rule_data_sym = notification_rule_data.inject({}){|memo,(k,v)|
      memo[k.to_sym] = v; memo
    }
    notification_rule_data_sym.delete(:contact_id)
    notification_rule_data_sym[:tags] = Set.new(notification_rule_data['tags'])
    notification_rule.should_receive(:as_json).and_return(json_data)
    notification_rule.should_receive(:save).and_return(true)
    Flapjack::Data::NotificationRuleR.should_receive(:new).
      with(notification_rule_data_sym).and_return(notification_rule)

    notification_rules = mock('notification_rules')
    notification_rules.should_receive(:<<).with(notification_rule)
    contact.should_receive(:notification_rules).and_return(notification_rules)

    post "/notification_rules", notification_rule_data.to_json,
      {'CONTENT_TYPE' => 'application/json'}
    last_response.should be_ok
    last_response.body.should == json_data.to_json
  end

  it "does not create a notification_rule for a contact that's not present" do
    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with(notification_rule_data['contact_id']).and_return(nil)

    post "/notification_rules", notification_rule_data.to_json,
      {'CONTENT_TYPE' => 'application/json'}
    last_response.should be_forbidden
  end

  it "does not create a notification_rule if a rule id is provided" do
    post "/notification_rules", notification_rule_data.merge(:id => '1').to_json,
      {'CONTENT_TYPE' => 'application/json'}
    last_response.status.should == 403
  end

  # PUT /notification_rules/RULE_ID
  it "updates a notification rule" do
    Flapjack::Data::NotificationRuleR.should_receive(:find_by_id).
      with(notification_rule.id).and_return(notification_rule)

    # symbolize the keys
    notification_rule_data_sym = notification_rule_data.inject({}){|memo,(k,v)|
      memo[k.to_sym] = v; memo
    }
    notification_rule_data_sym.delete(:contact_id)
    notification_rule_data_sym[:tags] = Set.new(notification_rule_data['tags'])
    notification_rule_data_sym.each_pair do |k,v|
      notification_rule.should_receive("#{k}=".to_sym).with(v)
    end
    notification_rule.should_receive(:save).and_return(true)
    notification_rule.should_receive(:as_json).and_return(json_data)

    put "/notification_rules/#{notification_rule.id}", notification_rule_data.to_json,
      {'CONTENT_TYPE' => 'application/json'}
    last_response.should be_ok
    last_response.body.should == json_data.to_json
  end

  it "does not update a notification rule that's not present" do
    Flapjack::Data::NotificationRuleR.should_receive(:find_by_id).
      with(notification_rule.id).and_return(nil)

    put "/notification_rules/#{notification_rule.id}", notification_rule_data
    last_response.should be_forbidden
  end

  # DELETE /notification_rules/RULE_ID
  it "deletes a notification rule" do
    Flapjack::Data::NotificationRuleR.should_receive(:find_by_id).
      with(notification_rule.id).and_return(notification_rule)

    notification_rule.should_receive(:contact).and_return(contact)

    notification_rule.should_receive(:destroy)
    notification_rules = mock('notification_rules')
    notification_rules.should_receive(:delete).with(notification_rule)
    contact.should_receive(:notification_rules).and_return(notification_rules)

    delete "/notification_rules/#{notification_rule.id}"
    last_response.status.should == 204
  end

  it "does not delete a notification rule that's not present" do
    Flapjack::Data::NotificationRuleR.should_receive(:find_by_id).
      with(notification_rule.id).and_return(nil)

    delete "/notification_rules/#{notification_rule.id}"
    last_response.should be_forbidden
  end

  it "does not delete a notification rule if the contact is not present" do
    Flapjack::Data::NotificationRuleR.should_receive(:find_by_id).
      with(notification_rule.id).and_return(notification_rule)

    notification_rule.should_receive(:contact).and_return(nil)

    delete "/notification_rules/#{notification_rule.id}"
    last_response.should be_forbidden
  end

  # GET /contacts/CONTACT_ID/media
  it "returns the media of a contact" do
    contact.should_receive(:media).and_return([json_data])
    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(contact)

    get "/contacts/0362/media"
    last_response.should be_ok
    last_response.body.should == [json_data].to_json
  end

  it "does not return the media of a contact if the contact is not present" do
    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(nil)

    get "/contacts/0362/media"
    last_response.should be_forbidden
  end

  # GET /contacts/CONTACT_ID/media/MEDIA
  it "returns the specified media of a contact" do
    medium = mock(Flapjack::Data::MediumR)
    medium.should_receive(:as_json).and_return(json_data)
    all_media = mock('all_media', :all => [medium])
    media = mock('media')
    media.should_receive(:intersect).with(:type => 'sms').and_return(all_media)
    contact.should_receive(:media).and_return(media)

    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(contact)

    get "/contacts/0362/media/sms"
    last_response.should be_ok
    last_response.body.should == json_data.to_json
  end

  it "does not return the media of a contact if the contact is not present" do
    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(nil)

    get "/contacts/0362/media/sms"
    last_response.should be_forbidden
  end

  it "does not return the media of a contact if the media is not present" do
    all_media = mock('all_media', :all => [])
    media = mock('media')
    media.should_receive(:intersect).with(:type => 'telepathy').and_return(all_media)
    contact.should_receive(:media).and_return(media)

    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(contact)

    get "/contacts/0362/media/telepathy"
    last_response.should be_forbidden
  end

  # PUT, DELETE /contacts/CONTACT_ID/media/MEDIA
  it "creates/updates a media of a contact" do
    medium = mock(Flapjack::Data::MediumR)
    medium.should_receive(:address=).with('04987654321')
    medium.should_receive(:interval=).with(200)
    medium.should_receive(:save).and_return(true)
    medium.should_receive(:as_json).and_return(json_data)

    all_media = mock('all_media', :all => [medium])

    media = mock('media')
    media.should_receive(:intersect).with(:type => 'sms').and_return(all_media)
    contact.should_receive(:media).and_return(media)

    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(contact)

    put "/contacts/0362/media/sms", {:address => '04987654321', :interval => '200'}
    last_response.should be_ok
    last_response.body.should == json_data.to_json
  end

  it "does not create a media of a contact that's not present" do
    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(nil)

    put "/contacts/0362/media/sms", {:address => '04987654321', :interval => '200'}
    last_response.should be_forbidden
  end

  it "does not create a media of a contact if no address is provided" do
    medium = mock(Flapjack::Data::MediumR)
    medium.should_receive(:address=).with(nil)
    medium.should_receive(:interval=).with(200)
    medium.should_receive(:save).and_return(false)
    errors = mock('errors', :full_messages => ['Address cannot be blank'])
    medium.should_receive(:errors).and_return(errors)

    all_media = mock('all_media', :all => [medium])

    media = mock('media')
    media.should_receive(:intersect).with(:type => 'sms').and_return(all_media)
    contact.should_receive(:media).and_return(media)

    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(contact)

    put "/contacts/0362/media/sms", {:interval => '200'}
    last_response.should be_forbidden
  end

  it "creates a media of a contact even if no interval is provided" do
    medium = mock(Flapjack::Data::MediumR)
    medium.should_receive(:address=).with('04987654321')
    medium.should_receive(:save).and_return(true)
    medium.should_receive(:as_json).and_return(json_data)
    Flapjack::Data::MediumR.should_receive(:new).and_return(medium)

    no_media = mock('no_media', :all => [])

    media = mock('media')
    media.should_receive(:intersect).with(:type => 'sms').and_return(no_media)
    media.should_receive(:<<).with(medium)
    contact.should_receive(:media).and_return(media)

    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(contact)

    put "/contacts/0362/media/sms", {:address => '04987654321'}
    last_response.should be_ok
  end

  it "deletes a media of a contact" do
    medium = mock(Flapjack::Data::MediumR)
    medium.should_receive(:destroy)

    all_media = mock('all_media', :all => [medium])

    media = mock('media')
    media.should_receive(:intersect).with(:type => 'sms').and_return(all_media)
    media.should_receive(:delete).with(medium)

    contact.should_receive(:media).and_return(media)
    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(contact)

    delete "/contacts/0362/media/sms"
    last_response.status.should == 204
  end

  it "does not delete a media of a contact that's not present" do
    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(nil)

    delete "/contacts/0362/media/sms"
    last_response.should be_forbidden
  end

  # GET /contacts/CONTACT_ID/timezone
  it "returns the timezone of a contact" do
    contact.should_receive(:timezone).and_return(::ActiveSupport::TimeZone.new('Australia/Sydney'))
    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(contact)

    get "/contacts/0362/timezone"
    last_response.should be_ok
    last_response.body.should be_json_eql('"Australia/Sydney"')
  end

  it "doesn't get the timezone of a contact that doesn't exist" do
    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(nil)

    get "/contacts/0362/timezone"
    last_response.should be_forbidden
  end

  # PUT /contacts/CONTACT_ID/timezone
  it "sets the timezone of a contact" do
    contact.should_receive(:timezone=).with('Australia/Perth')
    contact.should_receive(:save).and_return(true)
    contact.should_receive(:timezone).and_return(ActiveSupport::TimeZone.new('Australia/Perth'))
    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(contact)

    put "/contacts/0362/timezone", {:timezone => 'Australia/Perth'}
    last_response.should be_ok
  end

  it "doesn't set the timezone of a contact who can't be found" do
    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(nil)

    put "/contacts/0362/timezone", {:timezone => 'Australia/Perth'}
    last_response.should be_forbidden
  end

  # DELETE /contacts/CONTACT_ID/timezone
  it "deletes the timezone of a contact" do
    contact.should_receive(:timezone=).with(nil)
    contact.should_receive(:save).and_return(true)
    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(contact)

    delete "/contacts/0362/timezone"
    last_response.status.should == 204
  end

  it "does not delete the timezone of a contact that's not present" do
    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(nil)

    delete "/contacts/0362/timezone"
    last_response.should be_forbidden
  end

  it "sets a single tag on a contact and returns current tags" do
    tags = ['web']
    contact.should_receive(:tags=).with(Set.new(tags))
    contact.should_receive(:tags).twice.and_return(Set.new, Set.new(tags))
    contact.should_receive(:save).and_return(true)
    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(contact)

    post "contacts/0362/tags", :tag => tags.first
    last_response.should be_ok
    last_response.body.should be_json_eql( tags.to_json )
  end

  it "does not set a single tag on a contact that's not found" do
    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(nil)

    post "contacts/0362/tags", :tag => 'web'
    last_response.should be_forbidden
  end

  it "sets multiple tags on a contact and returns current tags" do
    tags = ['web', 'app']
    contact.should_receive(:tags=).with(Set.new(tags))
    contact.should_receive(:tags).twice.and_return(Set.new, Set.new(tags))
    contact.should_receive(:save).and_return(true)
    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(contact)

    # NB submitted at a lower level as tag[]=web&tag[]=app
    post "contacts/0362/tags", :tag => tags
    last_response.should be_ok
    last_response.body.should be_json_eql( tags.to_json )
  end

  it "does not set multiple tags on a contact that's not found" do
    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(nil)

    post "contacts/0362/tags", :tag => ['web', 'app']
    last_response.should be_forbidden
  end

  it "removes a single tag from a contact" do
    tags = ['web']
    contact.should_receive(:tags=).with(Set.new)
    contact.should_receive(:tags).and_return(Set.new(tags))
    contact.should_receive(:save).and_return(true)
    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(contact)

    delete "contacts/0362/tags", :tag => tags.first
    last_response.status.should == 204
  end

  it "does not remove a single tag from a contact that's not found" do
    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(nil)

    delete "contacts/0362/tags", :tag => 'web'
    last_response.should be_forbidden
  end

  it "removes multiple tags from a contact" do
    tags = ['web', 'app']
    contact.should_receive(:tags=).with(Set.new)
    contact.should_receive(:tags).and_return(Set.new(tags))
    contact.should_receive(:save).and_return(true)
    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(contact)

    delete "contacts/0362/tags", :tag => tags
    last_response.status.should == 204
  end

  it "does not remove multiple tags from a contact that's not found" do
    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(nil)

    delete "contacts/0362/tags", :tag => ['web', 'app']
    last_response.should be_forbidden
  end

  it "gets all tags on a contact" do
    contact.should_receive(:tags).and_return(Set.new(['web', 'app']))
    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(contact)

    get "contacts/0362/tags"
    last_response.should be_ok
    last_response.body.should be_json_eql( ['web', 'app'].to_json )
  end

  it "does not get all tags on a contact that's not found" do
    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(nil)

    get "contacts/0362/tags"
    last_response.should be_forbidden
  end

  it "gets all entity tags for a contact" do
    entity_1 = mock(Flapjack::Data::EntityR)
    entity_1.should_receive(:name).and_return('entity_1')
    entity_1.should_receive(:tags).and_return(Set.new(['web']))
    entity_2 = mock(Flapjack::Data::EntityR)
    entity_2.should_receive(:name).and_return('entity_2')
    entity_2.should_receive(:tags).and_return(Set.new(['app']))

    all_entities = mock('all_entities', :all => [entity_1, entity_2])
    contact.should_receive(:entities).and_return(all_entities)

    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(contact)

    get "contacts/0362/entity_tags"
    last_response.should be_ok
    tag_response = {'entity_1' => ['web'],
                    'entity_2' => ['app']}
    last_response.body.should be_json_eql( tag_response.to_json )
  end

  it "does not get all entity tags for a contact that's not found" do
    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(nil)

    get "contacts/0362/entity_tags"
    last_response.should be_forbidden
  end

  it "adds tags to multiple entities for a contact" do
    tags_1 = Set.new
    tags_2 = Set.new

    entity_1 = mock(Flapjack::Data::EntityR)
    entity_1.should_receive(:name).twice.and_return('entity_1')
    entity_1.should_receive(:tags).twice.and_return(tags_1, tags_1 + ['web'])
    entity_1.should_receive(:tags=).with(tags_1 + ['web'])
    entity_2 = mock(Flapjack::Data::EntityR)
    entity_2.should_receive(:name).twice.and_return('entity_2')
    entity_2.should_receive(:tags).twice.and_return(tags_2, tags_2 + ['app'])
    entity_2.should_receive(:tags=).with(tags_2 + ['app'])

    all_entities = mock('all_entities')
    all_entities.should_receive(:all).and_return([entity_1, entity_2])
    all_entities.should_receive(:each).and_yield(entity_1).and_yield(entity_2)

    contact.should_receive(:entities).and_return(all_entities)

    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(contact)

    post "contacts/0362/entity_tags",
      :entity => {'entity_1' => ['web'], 'entity_2' => ['app']}
    last_response.should be_ok
    tag_response = {'entity_1' => ['web'],
                    'entity_2' => ['app']}
    last_response.body.should be_json_eql( tag_response.to_json )
  end

  it "does not add tags to multiple entities for a contact that's not found" do
    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(nil)

    post "contacts/0362/entity_tags",
      :entity => {'entity_1' => ['web'], 'entity_2' => ['app']}
    last_response.should be_forbidden
  end

  it "deletes tags from multiple entities for a contact" do
    tags_1 = Set.new(['web'])
    tags_2 = Set.new(['app'])

    entity_1 = mock(Flapjack::Data::EntityR)
    entity_1.should_receive(:name).and_return('entity_1')
    entity_1.should_receive(:tags).and_return(tags_1)
    entity_1.should_receive(:tags=).with(tags_1 - ['web'])
    entity_2 = mock(Flapjack::Data::EntityR)
    entity_2.should_receive(:name).and_return('entity_2')
    entity_2.should_receive(:tags).and_return(tags_2)
    entity_2.should_receive(:tags=).with(tags_2 - ['app'])

    all_entities = mock('all_entities')
    all_entities.should_receive(:each).and_yield(entity_1).and_yield(entity_2)

    contact.should_receive(:entities).and_return(all_entities)

    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(contact)

    delete "contacts/0362/entity_tags",
      :entity => {'entity_1' => ['web'], 'entity_2' => ['app']}
    last_response.status.should == 204
  end

  it "does not delete tags from multiple entities for a contact that's not found" do
    Flapjack::Data::ContactR.should_receive(:find_by_id).
      with('0362').and_return(nil)

    delete "contacts/0362/entity_tags",
      :entity => {'entity_1' => ['web'], 'entity_2' => ['app']}
    last_response.should be_forbidden
  end

end
