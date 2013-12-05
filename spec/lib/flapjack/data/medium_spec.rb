require 'spec_helper'

require 'flapjack/data/medium'

describe Flapjack::Data::Medium, :redis => true do

  it "clears expired notification blocks" do
    t = Time.now

    Factory.entity(:name => 'foo.example.com', :id => '5')
    entity = Flapjack::Data::Entity.find_by_id('5')

    Factory.check(entity, :entity_name => entity.name, :name => 'PING',
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
    old_notification_block.save.should be_true

    new_notification_block = Flapjack::Data::NotificationBlock.new(
      :expire_at => t.to_i + (60 * 60), :state => 'critical')
    new_notification_block.save.should be_true

    check.notification_blocks << old_notification_block
    check.notification_blocks << new_notification_block

    medium.notification_blocks << old_notification_block <<
      new_notification_block

    Flapjack::Data::NotificationBlock.count.should == 2
    medium.drop_notifications?(:state => 'critical', :check => check).should be_true
    Flapjack::Data::NotificationBlock.count.should == 1
    remaining_block = Flapjack::Data::NotificationBlock.all.first
    remaining_block.should_not be_nil
    remaining_block.id.should == new_notification_block.id
  end

end
