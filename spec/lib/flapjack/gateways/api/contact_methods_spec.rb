require 'spec_helper'
require 'flapjack/gateways/api'

describe 'Flapjack::Gateways::API::ContactMethods', :sinatra => true, :logger => true do

  def app
    Flapjack::Gateways::API
  end

  let(:contact)         { double(Flapjack::Data::Contact, :id => '21') }
  let(:contact_core)    {
    {'id'         => contact.id,
     'first_name' => "Ada",
     'last_name'  => "Lovelace",
     'email'      => "ada@example.com",
     'tags'       => ["legend", "first computer programmer"]
    }
  }

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

  let(:media_rollup_thresholds) {
    {'email' => 5}
  }

  let(:redis)           { double(::Redis) }

  let(:notification_rule) {
    double(Flapjack::Data::NotificationRule, :id => '1', :contact_id => '21')
  }

  let(:notification_rule_data) {
    {"contact_id"         => "21",
     "tags"               => ["database","physical"],
     "regex_tags"         => ["^data.*$","^(physical|bare_metal)$"],
     "entities"           => ["foo-app-01.example.com"],
     "regex_entities"     => ["^foo-\S{3}-\d{2}.example.com$"],
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
    expect(Flapjack::RedisPool).to receive(:new).and_return(redis)
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

    expect(Flapjack::Data::Contact).to receive(:all).with(:redis => redis).and_return([])
    expect(Flapjack::Data::Contact).to receive(:add).twice

    apost "/contacts", contacts.to_json, {'CONTENT_TYPE' => 'application/json'}
    expect(last_response.status).to eq(204)
  end

  it "does not create contacts if the data is improperly formatted" do
    expect(Flapjack::Data::Contact).not_to receive(:add)

    apost "/contacts", {'contacts' => ["Hello", "again"]}.to_json,
      {'CONTENT_TYPE' => 'application/json'}
    expect(last_response.status).to eq(403)
  end

  it "does not create contacts if they don't contain an id" do
    contacts = {'contacts' =>
      [{"id" => "0362",
        "first_name" => "John",
        "last_name" => "Smith",
        "email" => "johns@example.dom",
        "media" => {"email"  => "johns@example.dom",
                    "jabber" => "johns@conference.localhost"}},
       {"first_name" => "Jane",
        "last_name" => "Jones",
        "email" => "jane@example.dom",
        "media" => {"email" => "jane@example.dom"}}
      ]
    }

    expect(Flapjack::Data::Contact).to receive(:all).with(:redis => redis).and_return([])
    expect(Flapjack::Data::Contact).to receive(:add)

    apost "/contacts", contacts.to_json, {'CONTENT_TYPE' => 'application/json'}
    expect(last_response.status).to eq(204)
  end

  it "updates a contact if it is already present" do
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

    existing = double(Flapjack::Data::Contact)
    expect(existing).to receive(:id).and_return("0363")
    expect(existing).to receive(:update).with(contacts['contacts'][1])

    expect(Flapjack::Data::Contact).to receive(:all).with(:redis => redis).and_return([existing])
    expect(Flapjack::Data::Contact).to receive(:add).with(contacts['contacts'][0], :redis => redis)

    apost "/contacts", contacts.to_json, {'CONTENT_TYPE' => 'application/json'}
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
    expect(existing).to receive(:delete!)

    expect(Flapjack::Data::Contact).to receive(:all).with(:redis => redis).and_return([existing])
    expect(Flapjack::Data::Contact).to receive(:add).with(contacts['contacts'][0], :redis => redis)

    apost "/contacts", contacts.to_json, {'CONTENT_TYPE' => 'application/json'}
    expect(last_response.status).to eq(204)
  end

  it "returns all the contacts" do
    expect(contact).to receive(:to_json).and_return(contact_core.to_json)
    expect(Flapjack::Data::Contact).to receive(:all).with(:redis => redis).
      and_return([contact])

    aget '/contacts'
    expect(last_response).to be_ok
    expect(last_response.body).to eq([contact_core].to_json)
  end

  it "returns the core information of a specified contact" do
    expect(contact).to receive(:to_json).and_return(contact_core.to_json)
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(contact)

    aget "/contacts/#{contact.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(contact_core.to_json)
  end

  it "does not return information for a contact that does not exist" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(nil)

    aget "/contacts/#{contact.id}"
    expect(last_response).to be_forbidden
  end

  it "lists a contact's notification rules" do
    notification_rule_2 = double(Flapjack::Data::NotificationRule, :id => '2', :contact_id => '21')
    expect(notification_rule).to receive(:to_json).and_return('"rule_1"')
    expect(notification_rule_2).to receive(:to_json).and_return('"rule_2"')
    notification_rules = [ notification_rule, notification_rule_2 ]

    expect(contact).to receive(:notification_rules).and_return(notification_rules)
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(contact)

    aget "/contacts/#{contact.id}/notification_rules"
    expect(last_response).to be_ok
    expect(last_response.body).to eq('["rule_1","rule_2"]')
  end

  it "does not list notification rules for a contact that does not exist" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(nil)

    aget "/contacts/#{contact.id}/notification_rules"
    expect(last_response).to be_forbidden
  end

  it "returns a specified notification rule" do
    expect(notification_rule).to receive(:to_json).and_return('"rule_1"')
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_id).
      with(notification_rule.id, {:redis => redis, :logger => @logger}).and_return(notification_rule)

    aget "/notification_rules/#{notification_rule.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq('"rule_1"')
  end

  it "does not return a notification rule that does not exist" do
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_id).
      with(notification_rule.id, {:redis => redis, :logger => @logger}).and_return(nil)

    aget "/notification_rules/#{notification_rule.id}"
    expect(last_response).to be_forbidden
  end

  # POST /notification_rules
  it "creates a new notification rule" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(contact)
    expect(notification_rule).to receive(:respond_to?).with(:critical_media).and_return(true)
    expect(notification_rule).to receive(:to_json).and_return('"rule_1"')

    # symbolize the keys
    notification_rule_data_sym = notification_rule_data.inject({}){|memo,(k,v)|
      memo[k.to_sym] = v; memo
    }
    notification_rule_data_sym.delete(:contact_id)

    expect(contact).to receive(:add_notification_rule).
      with(notification_rule_data_sym, :logger => @logger).and_return(notification_rule)

    apost "/notification_rules", notification_rule_data.to_json,
      {'CONTENT_TYPE' => 'application/json'}
    expect(last_response).to be_ok
    expect(last_response.body).to eq('"rule_1"')
  end

  it "does not create a notification_rule for a contact that's not present" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(nil)

    apost "/notification_rules", notification_rule_data.to_json,
      {'CONTENT_TYPE' => 'application/json'}
    expect(last_response).to be_forbidden
  end

  it "does not create a notification_rule if a rule id is provided" do
    expect(contact).not_to receive(:add_notification_rule)

    apost "/notification_rules", notification_rule_data.merge(:id => 1).to_json,
      {'CONTENT_TYPE' => 'application/json'}
    expect(last_response.status).to eq(403)
  end

  # PUT /notification_rules/RULE_ID
  it "updates a notification rule" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(contact)
    expect(notification_rule).to receive(:to_json).and_return('"rule_1"')
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_id).
      with(notification_rule.id, {:redis => redis, :logger => @logger}).and_return(notification_rule)

    # symbolize the keys
    notification_rule_data_sym = notification_rule_data.inject({}){|memo,(k,v)|
      memo[k.to_sym] = v; memo
    }
    notification_rule_data_sym.delete(:contact_id)

    expect(notification_rule).to receive(:update).with(notification_rule_data_sym, :logger => @logger).and_return(nil)

    aput "/notification_rules/#{notification_rule.id}", notification_rule_data.to_json,
      {'CONTENT_TYPE' => 'application/json'}
    expect(last_response).to be_ok
    expect(last_response.body).to eq('"rule_1"')
  end

  it "does not update a notification rule that's not present" do
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_id).
      with(notification_rule.id, {:redis => redis, :logger => @logger}).and_return(nil)

    aput "/notification_rules/#{notification_rule.id}", notification_rule_data
    expect(last_response).to be_forbidden
  end

  it "does not update a notification_rule for a contact that's not present" do
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_id).
      with(notification_rule.id, {:redis => redis, :logger => @logger}).and_return(notification_rule)
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(nil)

    aput "/notification_rules/#{notification_rule.id}", notification_rule_data.to_json,
      {'CONTENT_TYPE' => 'application/json'}
    expect(last_response).to be_forbidden
  end

  # DELETE /notification_rules/RULE_ID
  it "deletes a notification rule" do
    expect(notification_rule).to receive(:contact_id).and_return(contact.id)
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_id).
      with(notification_rule.id, {:redis => redis, :logger => @logger}).and_return(notification_rule)
    expect(contact).to receive(:delete_notification_rule).with(notification_rule)
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(contact)

    adelete "/notification_rules/#{notification_rule.id}"
    expect(last_response.status).to eq(204)
  end

  it "does not delete a notification rule that's not present" do
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_id).
      with(notification_rule.id, {:redis => redis, :logger => @logger}).and_return(nil)

    adelete "/notification_rules/#{notification_rule.id}"
    expect(last_response).to be_forbidden
  end

  it "does not delete a notification rule if the contact is not present" do
    expect(notification_rule).to receive(:contact_id).and_return(contact.id)
    expect(Flapjack::Data::NotificationRule).to receive(:find_by_id).
      with(notification_rule.id, {:redis => redis, :logger => @logger}).and_return(notification_rule)
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(nil)

    adelete "/notification_rules/#{notification_rule.id}"
    expect(last_response).to be_forbidden
  end

  # GET /contacts/CONTACT_ID/media
  it "returns the media of a contact" do
    expect(contact).to receive(:media).and_return(media)
    expect(contact).to receive(:media_intervals).and_return(media_intervals)
    expect(contact).to receive(:media_rollup_thresholds).and_return(media_rollup_thresholds)
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(contact)
    result = Hash[ *(media.keys.collect {|m|
      [m, {'address'          => media[m],
           'interval'         => media_intervals[m],
           'rollup_threshold' => media_rollup_thresholds[m] }]
      }).flatten(1)].to_json

    aget "/contacts/#{contact.id}/media"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result)
  end

  it "does not return the media of a contact if the contact is not present" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(nil)

    aget "/contacts/#{contact.id}/media"
    expect(last_response).to be_forbidden
  end

  # GET /contacts/CONTACT_ID/media/MEDIA
  it "returns the specified media of a contact" do
    expect(contact).to receive(:media).and_return(media)
    expect(contact).to receive(:media_intervals).and_return(media_intervals)
    expect(contact).to receive(:media_rollup_thresholds).and_return(media_rollup_thresholds)
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(contact)

    result = {
      'address'          => media['sms'],
      'interval'         => media_intervals['sms'],
      'rollup_threshold' => media_rollup_thresholds['sms'],
    }

    aget "/contacts/#{contact.id}/media/sms"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "does not return the media of a contact if the contact is not present" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(nil)

    aget "/contacts/#{contact.id}/media/sms"
    expect(last_response).to be_forbidden
  end

  it "does not return the media of a contact if the media is not present" do
    expect(contact).to receive(:media).and_return(media)
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(contact)

    aget "/contacts/#{contact.id}/media/telepathy"
    expect(last_response).to be_forbidden
  end

  # PUT, DELETE /contacts/CONTACT_ID/media/MEDIA
  it "creates/updates a media of a contact" do
    # as far as API is concerned these are the same -- contact.rb spec test
    # may distinguish between them
    alt_media = media.merge('sms' => '04987654321')
    alt_media_intervals = media_intervals.merge('sms' => '200')
    alt_media_rollup_thresholds = media_rollup_thresholds.merge('sms' => '5')

    expect(contact).to receive(:set_address_for_media).with('sms', '04987654321')
    expect(contact).to receive(:set_interval_for_media).with('sms', '200')
    expect(contact).to receive(:set_rollup_threshold_for_media).with('sms', '5')
    expect(contact).to receive(:media).and_return(alt_media)
    expect(contact).to receive(:media_intervals).and_return(alt_media_intervals)
    expect(contact).to receive(:media_rollup_thresholds).and_return(alt_media_rollup_thresholds)
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(contact)

    result = {'address'          => alt_media['sms'],
              'interval'         => alt_media_intervals['sms'],
              'rollup_threshold' => alt_media_rollup_thresholds['sms']}

    aput "/contacts/#{contact.id}/media/sms", :address => '04987654321',
      :interval => '200', :rollup_threshold => '5'
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "updates a contact's pagerduty media credentials" do
    result = {'service_key' => "flapjacktest@conference.jabber.sausage.net",
              'subdomain'   => "sausage.pagerduty.com",
              'username'    => "sausage@example.com",
              'password'    => "sausage"}

    expect(contact).to receive(:set_pagerduty_credentials).with(result)
    expect(contact).to receive(:pagerduty_credentials).and_return(result)
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(contact)

    aput "/contacts/#{contact.id}/media/pagerduty", :service_key => result['service_key'],
      :subdomain => result['subdomain'], :username => result['username'],
      :password => result['password']

    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  it "does not create a media of a contact that's not present" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(nil)

    aput "/contacts/#{contact.id}/media/sms", :address => '04987654321', :interval => '200'
    expect(last_response).to be_forbidden
  end

  it "does not create a media of a contact if no address is provided" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(contact)

    aput "/contacts/#{contact.id}/media/sms", :interval => '200'
    expect(last_response).to be_forbidden
  end

  it "creates a media of a contact even if no interval is provided" do
    alt_media = media.merge('sms' => '04987654321')
    alt_media_intervals = media_intervals.merge('sms' => nil)
    alt_media_rollup_thresholds = media_rollup_thresholds.merge('sms' => nil)

    expect(contact).to receive(:set_address_for_media).with('sms', '04987654321')
    expect(contact).to receive(:set_interval_for_media).with('sms', nil)
    expect(contact).to receive(:set_rollup_threshold_for_media).with("sms", nil)
    expect(contact).to receive(:media).and_return(alt_media)
    expect(contact).to receive(:media_intervals).and_return(alt_media_intervals)
    expect(contact).to receive(:media_rollup_thresholds).and_return(alt_media_rollup_thresholds)
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(contact)

    aput "/contacts/#{contact.id}/media/sms", :address => '04987654321'
    expect(last_response).to be_ok
  end

  it "deletes a media of a contact" do
    expect(contact).to receive(:remove_media).with('sms')
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(contact)

    adelete "/contacts/#{contact.id}/media/sms"
    expect(last_response.status).to eq(204)
  end

  it "does not delete a media of a contact that's not present" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(nil)

    adelete "/contacts/#{contact.id}/media/sms"
    expect(last_response).to be_forbidden
  end

  # GET /contacts/CONTACT_ID/timezone
  it "returns the timezone of a contact" do
    expect(contact).to receive(:timezone).and_return(::ActiveSupport::TimeZone.new('Australia/Sydney'))
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(contact)

    aget "/contacts/#{contact.id}/timezone"
    expect(last_response).to be_ok
    expect(last_response.body).to eq('"Australia/Sydney"')
  end

  it "doesn't get the timezone of a contact that doesn't exist" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(nil)

    aget "/contacts/#{contact.id}/timezone"
    expect(last_response).to be_forbidden
  end

  # PUT /contacts/CONTACT_ID/timezone
  it "sets the timezone of a contact" do
    expect(contact).to receive(:timezone=).with('Australia/Perth')
    expect(contact).to receive(:timezone).and_return(ActiveSupport::TimeZone.new('Australia/Perth'))
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(contact)

    aput "/contacts/#{contact.id}/timezone", {:timezone => 'Australia/Perth'}
    expect(last_response).to be_ok
  end

  it "doesn't set the timezone of a contact who can't be found" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(nil)

    aput "/contacts/#{contact.id}/timezone", {:timezone => 'Australia/Perth'}
    expect(last_response).to be_forbidden
  end

  # DELETE /contacts/CONTACT_ID/timezone
  it "deletes the timezone of a contact" do
    expect(contact).to receive(:timezone=).with(nil)
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(contact)

    adelete "/contacts/#{contact.id}/timezone"
    expect(last_response.status).to eq(204)
  end

  it "does not delete the timezone of a contact that's not present" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(nil)

    adelete "/contacts/#{contact.id}/timezone"
    expect(last_response).to be_forbidden
  end

  it "sets a single tag on a contact and returns current tags" do
    expect(contact).to receive(:add_tags).with('web')
    expect(contact).to receive(:tags).and_return(['web'])
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(contact)

    apost "contacts/#{contact.id}/tags", :tag => 'web'
    expect(last_response).to be_ok
    expect(last_response.body).to eq(['web'].to_json)
  end

  it "does not set a single tag on a contact that's not found" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(nil)

    apost "contacts/#{contact.id}/tags", :tag => 'web'
    expect(last_response).to be_forbidden
  end

  it "sets multiple tags on a contact and returns current tags" do
    expect(contact).to receive(:add_tags).with('web', 'app')
    expect(contact).to receive(:tags).and_return(['web', 'app'])
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(contact)

    apost "contacts/#{contact.id}/tags", :tag => ['web', 'app']
    expect(last_response).to be_ok
    expect(last_response.body).to eq(['web', 'app'].to_json)
  end

  it "does not set multiple tags on a contact that's not found" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(nil)

    apost "contacts/#{contact.id}/tags", :tag => ['web', 'app']
    expect(last_response).to be_forbidden
  end

  it "removes a single tag from a contact" do
    expect(contact).to receive(:delete_tags).with('web')
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(contact)

    adelete "contacts/#{contact.id}/tags", :tag => 'web'
    expect(last_response.status).to eq(204)
  end

  it "does not remove a single tag from a contact that's not found" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(nil)

    adelete "contacts/#{contact.id}/tags", :tag => 'web'
    expect(last_response).to be_forbidden
  end

  it "removes multiple tags from a contact" do
    expect(contact).to receive(:delete_tags).with('web', 'app')
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(contact)

    adelete "contacts/#{contact.id}/tags", :tag => ['web', 'app']
    expect(last_response.status).to eq(204)
  end

  it "does not remove multiple tags from a contact that's not found" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(nil)

    adelete "contacts/#{contact.id}/tags", :tag => ['web', 'app']
    expect(last_response).to be_forbidden
  end

  it "gets all tags on a contact" do
    expect(contact).to receive(:tags).and_return(['web', 'app'])
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(contact)

    aget "contacts/#{contact.id}/tags"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(['web', 'app'].to_json)
  end

  it "does not get all tags on a contact that's not found" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(nil)

    aget "contacts/#{contact.id}/tags"
    expect(last_response).to be_forbidden
  end

  it "gets all entity tags for a contact" do
    entity_1 = double(Flapjack::Data::Entity)
    expect(entity_1).to receive(:name).and_return('entity_1')
    entity_2 = double(Flapjack::Data::Entity)
    expect(entity_2).to receive(:name).and_return('entity_2')
    tag_data = [{:entity => entity_1, :tags => ['web']},
                {:entity => entity_2, :tags => ['app']}]
    expect(contact).to receive(:entities).with(:tags => true).
      and_return(tag_data)

    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(contact)

    aget "contacts/#{contact.id}/entity_tags"
    expect(last_response).to be_ok
    tag_response = {'entity_1' => ['web'],
                    'entity_2' => ['app']}
    expect(last_response.body).to eq(tag_response.to_json)
  end

  it "does not get all entity tags for a contact that's not found" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(nil)

    aget "contacts/#{contact.id}/entity_tags"
    expect(last_response).to be_forbidden
  end

  it "adds tags to multiple entities for a contact" do
    entity_1 = double(Flapjack::Data::Entity)
    expect(entity_1).to receive(:name).twice.and_return('entity_1')
    expect(entity_1).to receive(:add_tags).with('web')
    entity_2 = double(Flapjack::Data::Entity)
    expect(entity_2).to receive(:name).twice.and_return('entity_2')
    expect(entity_2).to receive(:add_tags).with('app')

    entities = [{:entity => entity_1}, {:entity => entity_2}]
    expect(contact).to receive(:entities).and_return(entities)
    tag_data = [{:entity => entity_1, :tags => ['web']},
                {:entity => entity_2, :tags => ['app']}]
    expect(contact).to receive(:entities).with(:tags => true).and_return(tag_data)

    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(contact)

    apost "contacts/#{contact.id}/entity_tags",
      :entity => {'entity_1' => ['web'], 'entity_2' => ['app']}
    expect(last_response).to be_ok
    tag_response = {'entity_1' => ['web'],
                    'entity_2' => ['app']}
    expect(last_response.body).to  eq(tag_response.to_json)
  end

  it "does not add tags to multiple entities for a contact that's not found" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(nil)

    apost "contacts/#{contact.id}/entity_tags",
      :entity => {'entity_1' => ['web'], 'entity_2' => ['app']}
    expect(last_response).to be_forbidden
  end

  it "deletes tags from multiple entities for a contact" do
    entity_1 = double(Flapjack::Data::Entity)
    expect(entity_1).to receive(:name).and_return('entity_1')
    expect(entity_1).to receive(:delete_tags).with('web')
    entity_2 = double(Flapjack::Data::Entity)
    expect(entity_2).to receive(:name).and_return('entity_2')
    expect(entity_2).to receive(:delete_tags).with('app')

    entities = [{:entity => entity_1}, {:entity => entity_2}]
    expect(contact).to receive(:entities).and_return(entities)

    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(contact)

    adelete "contacts/#{contact.id}/entity_tags",
      :entity => {'entity_1' => ['web'], 'entity_2' => ['app']}
    expect(last_response.status).to eq(204)
  end

  it "does not delete tags from multiple entities for a contact that's not found" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, {:redis => redis, :logger => @logger}).and_return(nil)

    adelete "contacts/#{contact.id}/entity_tags",
      :entity => {'entity_1' => ['web'], 'entity_2' => ['app']}
    expect(last_response).to be_forbidden
  end


end
