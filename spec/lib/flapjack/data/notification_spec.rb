require 'spec_helper'
require 'flapjack/data/notification'

describe Flapjack::Data::Notification, :redis => true, :logger => true do

  let(:event)   { mock(Flapjack::Data::Event) }

  let(:contact) { mock(Flapjack::Data::Contact) }

  let(:timezone) { mock('timezone') }

  it "generates a notification for an event" do
    notification = Flapjack::Data::Notification.for_event(event, :type => 'problem',
      :max_notified_severity => nil, :contacts => [contact],
      :default_timezone => timezone, :logger => @logger)
    notification.should_not be_nil
    notification.event.should == event
    notification.type.should == 'problem'
  end

  it "generates messages for contacts" do
    notification = Flapjack::Data::Notification.for_event(event, :type => 'problem',
      :max_notified_severity => nil, :contacts => [contact],
      :default_timezone => timezone, :logger => @logger)

    contact.should_receive(:id).and_return('23')
    contact.should_receive(:notification_rules).and_return([])
    contact.should_receive(:media).and_return('email' => 'example@example.com',
                                              'sms'   => '0123456789')

    event.should_receive(:id).and_return('abc-123.com:ping')
    event.should_receive(:state).and_return('critical')
    event.should_receive(:summary).and_return('Shiny & happy')
    event.should_receive(:details).and_return('Really Shiny & happy')
    event.should_receive(:time).and_return(Time.now.to_i)
    event.should_receive(:duration).and_return(nil)

    messages = notification.messages
    messages.should_not be_nil
    messages.should have(2).items

    messages.first.contact.should == contact
    messages.first.medium.should == 'email'
    messages.first.address.should == 'example@example.com'

    messages.last.contact.should == contact
    messages.last.medium.should  == 'sms'
    messages.last.address.should == '0123456789'
  end

end
