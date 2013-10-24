require 'spec_helper'
require 'flapjack/data/notification'

describe Flapjack::Data::Notification, :redis => true, :logger => true do

  let(:event)   { double(Flapjack::Data::Event) }

  let(:entity_check) { double(Flapjack::Data::Check) }
  let(:check_state) { double(Flapjack::Data::CheckState) }

  let(:contact) { double(Flapjack::Data::Contact) }

  let(:timezone) { double('timezone') }

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
    notification = Flapjack::Data::Notification.new(
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
    entity_check.should_receive(:id).twice.and_return('abcde')

    Flapjack::Data::Check.should_receive(:find_by_id).with('abcde').and_return(entity_check)

    check_state.should_receive(:state).and_return('critical')

    Flapjack::Data::CheckState.should_receive(:find_by_id).with('fghij').and_return(check_state)

    alerting_checks_1 = double('alerting_checks_1')
    alerting_checks_1.should_receive(:exists?).with('abcde').and_return(false)
    alerting_checks_1.should_receive(:<<).with(entity_check)
    alerting_checks_1.should_receive(:count).and_return(1)

    alerting_checks_2 = double('alerting_checks_1')
    alerting_checks_2.should_receive(:exists?).with('abcde').and_return(false)
    alerting_checks_2.should_receive(:<<).with(entity_check)
    alerting_checks_2.should_receive(:count).and_return(1)

    medium_1 = double(Flapjack::Data::Medium)
    medium_1.should_receive(:type).twice.and_return('email')
    medium_1.should_receive(:address).twice.and_return('example@example.com')
    medium_1.should_receive(:alerting_checks).exactly(3).times.and_return(alerting_checks_1)
    medium_1.should_receive(:clean_alerting_checks).and_return(0)
    medium_1.should_receive(:rollup_threshold).exactly(3).times.and_return(10)

    medium_2 = double(Flapjack::Data::Medium)
    medium_2.should_receive(:type).twice.and_return('sms')
    medium_2.should_receive(:address).twice.and_return('0123456789')
    medium_2.should_receive(:alerting_checks).exactly(3).times.and_return(alerting_checks_2)
    medium_2.should_receive(:clean_alerting_checks).and_return(0)
    medium_2.should_receive(:rollup_threshold).exactly(3).times.and_return(10)

    message_1 = double(Flapjack::Data::Message)
    message_2 = double(Flapjack::Data::Message)

    Flapjack::Data::Message.should_receive(:for_contact).
      with(contact, :medium => 'email', :address => 'example@example.com', :rollup => nil).
      and_return(message_1)

    Flapjack::Data::Message.should_receive(:for_contact).
      with(contact, :medium => 'sms', :address => '0123456789', :rollup => nil).
      and_return(message_2)

    contact.should_receive(:id).and_return('23')
    contact.should_receive(:notification_rules).and_return([])
    all_media = double('all_media', :all => [medium_1, medium_2])
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
