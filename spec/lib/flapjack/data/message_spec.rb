require 'spec_helper'
require 'flapjack/data/message'

describe Flapjack::Data::Message do

  let(:contact) { double(Flapjack::Data::Contact) }

  it "assigns itself an ID" do
    message = Flapjack::Data::Message.for_contact(contact)
    mid = message.id
    expect(mid).not_to be_nil
    expect(mid).to be_a(String)
  end

  it "returns its contained data" do
    message = Flapjack::Data::Message.for_contact(contact, :medium => 'email',
                :address => 'jja@example.com')

    expect(contact).to receive(:id).and_return('23')
    expect(contact).to receive(:first_name).and_return('James')
    expect(contact).to receive(:last_name).and_return('Jameson')

    expect(message.contents).to include('contact_id' => '23',
                                    'contact_first_name' => 'James',
                                    'contact_last_name' => 'Jameson',
                                    'media' => 'email',
                                    'address' => 'jja@example.com')
  end

end