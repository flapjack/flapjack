require 'spec_helper'

require 'flapjack/data/contact'
require 'securerandom'

describe Flapjack::Data::Contact, :redis => true do

  let(:redis) { Flapjack.redis }

  context 'timezone' do

    it "sets a timezone string from a string" do
      cid = SecureRandom.uuid
      Factory.contact(:id => cid, :name => 'John Smith')
      contact = Flapjack::Data::Contact.find_by_id(cid)
      expect(contact.timezone).to be_nil

      contact.time_zone = 'Australia/Adelaide'
      expect(contact.save).to be_truthy
      expect(contact.timezone).to eq('Australia/Adelaide')
      expect(contact.time_zone).to respond_to(:name)
      expect(contact.time_zone.name).to eq('Australia/Adelaide')
    end

    it "sets a timezone string from a time zone"

    it "clears timezone string when set to nil"

    it "returns a time zone"

  end

end
