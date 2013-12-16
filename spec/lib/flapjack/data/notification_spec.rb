require 'spec_helper'
require 'flapjack/data/notification'

describe Flapjack::Data::Notification, :redis => true, :logger => true do

  let(:event)   { double(Flapjack::Data::Event) }

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
    notification = Flapjack::Data::Notification.new

    expect(contact).to receive(:id).and_return('23')
    expect(contact).to receive(:notification_rules).and_return([])
    expect(contact).to receive(:media).and_return('email' => 'example@example.com',
                                              'sms'   => '0123456789')
    expect(contact).to receive(:add_alerting_check_for_media).with("email", nil)
    expect(contact).to receive(:add_alerting_check_for_media).with("sms", nil)
    expect(contact).to receive(:clean_alerting_checks_for_media).with("email").and_return(0)
    expect(contact).to receive(:clean_alerting_checks_for_media).with("sms").and_return(0)
    expect(contact).to receive(:count_alerting_checks_for_media).with("email").and_return(0)
    expect(contact).to receive(:count_alerting_checks_for_media).with("sms").and_return(0)
    expect(contact).to receive(:rollup_threshold_for_media).with("email").and_return(nil)
    expect(contact).to receive(:rollup_threshold_for_media).with("sms").and_return(nil)

    messages = notification.messages([contact], :default_timezone => timezone,
      :logger => @logger)
    expect(messages).not_to be_nil
    expect(messages.size).to eq(2)

    expect(messages.first.contact).to eq(contact)
    expect(messages.first.medium).to eq('email')
    expect(messages.first.address).to eq('example@example.com')

    expect(messages.last.contact).to eq(contact)
    expect(messages.last.medium).to  eq('sms')
    expect(messages.last.address).to eq('0123456789')
  end

end
