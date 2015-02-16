require 'spec_helper'

require 'flapjack/data/contact'
require 'securerandom'

describe Flapjack::Data::Contact, :redis => true do

  let(:redis) { Flapjack.redis }

  let(:contact) {
    Factory.contact(:name => 'John Smith')
    Flapjack::Data::Contact.intersect(:name => 'John Smith').all.first
  }

  context 'timezone' do

    it "sets a timezone from a time zone string" do
      expect(contact.timezone).to be_nil
      expect(contact.time_zone).to be_nil

      contact.timezone = 'Australia/Adelaide'
      expect(contact.save).to be_truthy
      expect(contact.timezone).to eq('Australia/Adelaide')
      expect(contact.time_zone).to respond_to(:name)
      expect(contact.time_zone.name).to eq('Australia/Adelaide')
    end

    it "clears timezone when time zone string set to nil" do
      contact.timezone = 'Australia/Adelaide'
      expect(contact.save).to be_truthy

      contact.timezone = nil
      expect(contact.save).to be_truthy
      expect(contact.timezone).to be_nil
      expect(contact.time_zone).to be_nil
    end

    it "handles an invalid time zone string" do
      contact.timezone = ''
      expect(contact.save).to be_falsey
      expect(contact.errors.full_messages).to eq(['Timezone must be a valid time zone string'])
    end

  end

end
