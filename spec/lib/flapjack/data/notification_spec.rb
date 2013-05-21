require 'spec_helper'
require 'flapjack/data/notification'

describe Flapjack::Data::Notification, :redis => true do

  let(:event) { mock(Flapjack::Data::Event) }

  let(:contact) { mock(Flapjack::Data::Contact) }

  it "generates a notification for an event" do
    notification = Flapjack::Data::Notification.for_event(event, :type => 'problem',
      :max_notified_severity => nil)
    notification.should_not be_nil
    notification.event.should == event
    notification.type.should == 'problem'
  end

  it "generates messages for contacts" do
    notification = Flapjack::Data::Notification.for_event(event, :type => 'problem',
      :max_notified_severity => nil)
    contact.should_receive(:media).and_return('email' => 'example@example.com',
                                              'sms'   => '0123456789')

    messages = notification.messages(:contacts => [contact])
    messages.should_not be_nil
    messages.should have(2).items

    messages.first.notification.should == notification
    messages.first.contact.should == contact
    messages.first.medium.should == 'email'
    messages.first.address.should == 'example@example.com'

    messages.last.notification.should == notification
    messages.last.contact.should == contact
    messages.last.medium.should  == 'sms'
    messages.last.address.should == '0123456789'
  end

  it "returns its contained data" do
    notification = Flapjack::Data::Notification.for_event(event, :type => 'problem',
      :max_notified_severity => nil)

    t = Time.now.to_i

    event.should_receive(:id).and_return('example.com:ping')
    event.should_receive(:state).and_return('ok')
    event.should_receive(:summary).and_return('Shiny & happy')
    event.should_receive(:time).and_return(t)
    event.should_receive(:duration).and_return(nil)

    notification.contents.should == {'event_id'              => 'example.com:ping',
                                     'state'                 => 'ok',
                                     'summary'               => 'Shiny & happy',
                                     'time'                  => t,
                                     'duration'              => nil,
                                     'notification_type'     => 'problem',
                                     'max_notified_severity' => nil}

  end

end