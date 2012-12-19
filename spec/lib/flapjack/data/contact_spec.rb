require 'spec_helper'

require 'flapjack/data/contact'
require 'flapjack/data/entity_check'

describe Flapjack::Data::Contact, :redis => true do

  before(:each) do
    Flapjack::Data::Contact.add({'id'         => '362',
                                 'first_name' => 'John',
                                 'last_name'  => 'Johnson',
                                 'email'      => 'johnj@example.com',
                                 'media' => {
                                    'pagerduty' => {
                                      'service_key' => '123456789012345678901234',
                                      'subdomain'   => 'flpjck',
                                      'username'    => 'flapjack',
                                      'password'    => 'very_secure'
                                    }
                                  }},
                                 :redis       => @redis)

    Flapjack::Data::Contact.add({'id'         => '363',
                                 'first_name' => 'Jane',
                                 'last_name'  => 'Janeley',
                                 'email'      => 'janej@example.com'},
                                 :redis       => @redis)
  end

  it "returns a list of all contacts" do
    contacts = Flapjack::Data::Contact.all(:redis => @redis)
    contacts.should_not be_nil
    contacts.should be_an(Array)
    contacts.should have(2).contacts
    contacts[0].name.should == 'Jane Janeley'
    contacts[1].name.should == 'John Johnson'
  end

  it "finds a contact by id" do
    contact = Flapjack::Data::Contact.find_by_id('362', :redis => @redis)
    contact.should_not be_nil
    contact.name.should == "John Johnson"
  end

  it "deletes all contacts" do
    Flapjack::Data::Contact.delete_all(:redis => @redis)
    contact = Flapjack::Data::Contact.find_by_id('362', :redis => @redis)
    contact.should be_nil
    contact = Flapjack::Data::Contact.find_by_id('363', :redis => @redis)
    contact.should be_nil
  end

  it "returns a list of entities and their checks for a contact" do
    entity_name = 'abc-123'

    Flapjack::Data::Entity.add({'id'   => '5000',
                                'name' => entity_name,
                                'contacts' => ['362']},
                                :redis => @redis)

    ec = Flapjack::Data::EntityCheck.for_entity_name(entity_name, 'PING', :redis => @redis)
    t = Time.now.to_i
    ec.update_state('ok', :timestamp => t, :summary => 'a')

    contact = Flapjack::Data::Contact.find_by_id('362', :redis => @redis)
    eandcs = contact.entities_and_checks
    eandcs.should_not be_nil
    eandcs.should be_an(Array)
    eandcs.should have(1).entity_and_checks

    eandc = eandcs.first
    eandc.should be_a(Hash)

    entity = eandc[:entity]
    entity.name.should == entity_name
    checks = eandc[:checks]
    checks.should be_a(Set)
    checks.should have(1).check
    checks.should include('PING')
  end

  it "returns pagerduty credentials for a contact" do
    contact = Flapjack::Data::Contact.find_by_id('362', :redis => @redis)
    credentials = contact.pagerduty_credentials
    credentials.should_not be_nil
    credentials.should be_a(Hash)
    credentials.should == {'service_key' => '123456789012345678901234',
                           'subdomain'   => 'flpjck',
                           'username'    => 'flapjack',
                           'password'    => 'very_secure'}
  end

end
