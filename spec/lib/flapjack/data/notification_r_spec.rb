require 'spec_helper'
require 'flapjack/data/notification_r'

describe Flapjack::Data::NotificationR, :redis => true, :logger => true do

  let(:event)   { mock(Flapjack::Data::Event) }

  let(:entity_check) { mock(Flapjack::Data::EntityCheckR) }
  let(:check_state) { mock(Flapjack::Data::CheckStateR) }

  let(:contact) { mock(Flapjack::Data::ContactR) }

  let(:timezone) { mock('timezone') }

  it "generates a notification for an event" # do
  #   notification = Flapjack::Data::Notification.for_event(event, :type => 'problem',
  #     :max_notified_severity => nil, :contacts => [contact],
  #     :default_timezone => timezone, :logger => @logger)
  #   notification.should_not be_nil
  #   notification.event.should == event
  #   notification.type.should == 'problem'
  # end

  it "generates messages for contacts" do
    # TODO sensible default values for notification, check that they're passed
    # in message.notification_contents
    notification = Flapjack::Data::NotificationR.new(
      :entity_check_id   => 'abcde',
      :state_id          => 'fghij',
      :state_duration    => 16,
      :previous_state_id => nil,
      :severity          => 'critical',
      :type              => 'problem',
      :time              => Time.now,
      :duration          => nil,
      :tags              => Set.new
      )

    entity_check.should_receive(:entity_name).and_return('example.com')
    entity_check.should_receive(:name).and_return('ping')

    Flapjack::Data::EntityCheckR.should_receive(:find_by_id).with('abcde').and_return(entity_check)

    check_state.should_receive(:state).and_return('critical')

    Flapjack::Data::CheckStateR.should_receive(:find_by_id).with('fghij').and_return(check_state)

    medium_1 = mock(Flapjack::Data::MediumR)
    medium_1.should_receive(:type).and_return('email')
    medium_1.should_receive(:address).and_return('example@example.com')

    medium_2 = mock(Flapjack::Data::MediumR)
    medium_2.should_receive(:type).and_return('sms')
    medium_2.should_receive(:address).and_return('0123456789')

    message_1 = mock(Flapjack::Data::Message)
    message_2 = mock(Flapjack::Data::Message)

    Flapjack::Data::Message.should_receive(:for_contact).
      with(contact, :medium => 'email', :address => 'example@example.com').
      and_return(message_1)

    Flapjack::Data::Message.should_receive(:for_contact).
      with(contact, :medium => 'sms', :address => '0123456789').
      and_return(message_2)

    contact.should_receive(:id).and_return('23')
    contact.should_receive(:notification_rules).and_return([])
    all_media = mock('all_media', :all => [medium_1, medium_2])
    all_media.should_receive(:collect).and_yield(medium_1).
                                         and_yield(medium_2).and_return([message_1, message_2])
    contact.should_receive(:media).and_return(all_media)

    messages = notification.messages([contact], :default_timezone => timezone,
      :logger => @logger)
    messages.should_not be_nil
    messages.should have(2).items
    messages.should == [message_1, message_2]
  end

end
