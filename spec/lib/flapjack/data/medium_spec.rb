require 'spec_helper'

require 'flapjack/data/medium'

describe Flapjack::Data::Medium, :redis => true do

  it "clears expired notification blocks" do
    t = Time.now

    Factory.check(:name => 'foo.example.com:PING',
      :id => 1, :enabled => true)
    check = Flapjack::Data::Check.find_by_id('1')

    Factory.contact(:id => '1', :first_name => 'John', :last_name => 'Smith',
      :email => 'jsmith@example.com') # raw redis
    contact = Flapjack::Data::Contact.find_by_id('1')

    Factory.medium(contact, :id => '10', :type => 'sms', :address => '012345678',
      :interval => 60, :rollup_threshold => 2)
    medium = Flapjack::Data::Medium.find_by_id('10')
    contact.media << medium

    old_notification_block = Flapjack::Data::NotificationBlock.new(
      :expire_at => t.to_i - (60 * 60), :state => 'critical')
    expect(old_notification_block.save).to be_truthy

    new_notification_block = Flapjack::Data::NotificationBlock.new(
      :expire_at => t.to_i + (60 * 60), :state => 'critical')
    expect(new_notification_block.save).to be_truthy

    check.notification_blocks << old_notification_block
    check.notification_blocks << new_notification_block

    medium.notification_blocks << old_notification_block <<
      new_notification_block

    expect(Flapjack::Data::NotificationBlock.count).to eq(2)
    expect(medium.drop_notifications?(:state => 'critical', :check => check)).to be_truthy
    expect(Flapjack::Data::NotificationBlock.count).to eq(1)
    remaining_block = Flapjack::Data::NotificationBlock.all.first
    expect(remaining_block).not_to be_nil
    expect(remaining_block.id).to eq(new_notification_block.id)
  end

end
