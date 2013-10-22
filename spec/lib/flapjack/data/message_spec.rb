require 'spec_helper'
require 'flapjack/data/message'

describe Flapjack::Data::Message do

  let(:contact) { mock(Flapjack::Data::Contact) }

  it "assigns itself an ID" do
    message = Flapjack::Data::Message.for_contact(contact)
    mid = message.id
    mid.should_not be_nil
    mid.should be_a(String)
  end

  it "returns its contained data" do
    message = Flapjack::Data::Message.for_contact(contact, :medium => 'email',
                :address => 'jja@example.com')

    contact.should_receive(:id).and_return('23')
    contact.should_receive(:first_name).and_return('James')
    contact.should_receive(:last_name).and_return('Jameson')

    message.contents.should include('contact_id' => '23',
                                    'contact_first_name' => 'James',
                                    'contact_last_name' => 'Jameson',
                                    'media' => 'email',
                                    'address' => 'jja@example.com')
  end

end