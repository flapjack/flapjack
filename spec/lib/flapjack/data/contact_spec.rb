require 'spec_helper'

require 'flapjack/data/contact'

describe Flapjack::Data::Contact, :redis => true do

  it "returns a list of all contacts" do
    Flapjack::Data::Contact.add({'id'         => '362',
                                 'first_name' => 'John',
                                 'last_name'  => 'Johnson',
                                 'email'      => 'johnj@example.com' },
                                 :redis       => @redis)
    Flapjack::Data::Contact.add({'id'         => '363',
                                 'first_name' => 'Jane',
                                 'last_name'  => 'Janeley',
                                 'email'      => 'janej@example.com'},
                                 :redis       => @redis)

    contacts = Flapjack::Data::Contact.all(:redis => @redis)
    contacts.should_not be_nil
    contacts.should be_an(Array)
    contacts.should have(2).contacts
    contacts[0].id.should == '362'
    contacts[1].id.should == '363'
  end

  it "finds a contact by id" do
    Flapjack::Data::Contact.add({'id'         => '362',
                                 'first_name' => 'John',
                                 'last_name'  => 'Johnson',
                                 'email'      => 'johnj@example.com' },
                                 :redis       => @redis)

    contact = Flapjack::Data::Contact.find_by_id('362', :redis => @redis)
    contact.should_not be_nil
    contact.name.should == "John Johnson"
  end

  it "finds all contacts for a check on an entity"

  it "deletes all contacts"

  it "returns pagerduty credentials for a contact"

  it "returns a list of entities for a contact"

end
