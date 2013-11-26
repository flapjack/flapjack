require 'spec_helper'
require 'flapjack/gateways/email'

describe Flapjack::Gateways::Email, :logger => true do

  let(:redis) { double(::Redis) }

  let(:lock)  { double(Monitor) }

  let(:queue) { double(Flapjack::RecordQueue) }
  let(:alert) { double(Flapjack::Data::Alert) }

  it "sends a mail with text and html parts" do
    redis.should_receive(:quit)
    Flapjack.stub(:redis).and_return(redis)

    Flapjack::RecordQueue.should_receive(:new).with('email_notifications',
      Flapjack::Data::Alert).and_return(queue)

    lock.should_receive(:synchronize).and_yield
    queue.should_receive(:foreach).and_yield(alert)
    queue.should_receive(:wait).and_raise(Flapjack::PikeletStop)

    check = double(Flapjack::Data::Check)
    check.should_receive(:entity_name).exactly(3).times.and_return('example.com')
    check.should_receive(:name).exactly(3).times.and_return('ping')

    contact = double(Flapjack::Data::Contact)
    contact.should_receive(:first_name).twice.and_return('John')

    medium = double(Flapjack::Data::Medium)
    medium.should_receive(:contact).twice.and_return(contact)
    medium.should_receive(:address).and_return('johns@example.com')

    alert.should_receive(:id).and_return('123456')

    alert.should_receive(:medium).exactly(3).times.and_return(medium)

    alert.should_receive(:check).exactly(3).times.and_return(check)
    alert.should_receive(:state_title_case).exactly(3).times.and_return('OK')
    alert.should_receive(:state_duration).twice.and_return(2)
    alert.should_receive(:summary).twice.and_return('smile')
    alert.should_receive(:details).twice.and_return('')
    alert.should_receive(:time).twice.and_return(Time.now)

    alert.should_receive(:last_state).twice.and_return( double(Flapjack::Data::CheckState) )
    alert.should_receive(:last_state_title_case).twice.and_return('Critical')
    alert.should_receive(:last_summary).twice.and_return('frown')

    alert.should_receive(:notification_type).and_return('recovery')
    alert.should_receive(:type_sentence_case).and_return('Recovery')
    alert.should_receive(:rollup).and_return(nil)

    Mail::TestMailer.deliveries.should be_empty

    email_gw = Flapjack::Gateways::Email.new(:lock => lock, :config => {}, :logger => @logger)
    expect { email_gw.start }.to raise_error(Flapjack::PikeletStop)

    Mail::TestMailer.deliveries.should have(1).mail
  end

end
