require 'spec_helper'
require 'flapjack/gateways/email'

describe Flapjack::Gateways::Email, :logger => true do

  let(:redis) { double(::Redis) }

  let(:lock)  { double(Monitor) }

  let(:queue) { double(Flapjack::RecordQueue) }
  let(:alert) { double(Flapjack::Data::Alert) }

  it "sends a mail with text and html parts and custom from address" do
    expect(redis).to receive(:quit)
    allow(Flapjack).to receive(:redis).and_return(redis)

    expect(Flapjack::RecordQueue).to receive(:new).with('email_notifications',
      Flapjack::Data::Alert).and_return(queue)

    expect(lock).to receive(:synchronize).and_yield
    expect(queue).to receive(:foreach).and_yield(alert)
    expect(queue).to receive(:wait).and_raise(Flapjack::PikeletStop)

    check = double(Flapjack::Data::Check)
    expect(check).to receive(:entity_name).exactly(3).times.and_return('example.com')
    expect(check).to receive(:name).exactly(3).times.and_return('ping')

    contact = double(Flapjack::Data::Contact)
    expect(contact).to receive(:first_name).twice.and_return('John')

    medium = double(Flapjack::Data::Medium)
    expect(medium).to receive(:contact).twice.and_return(contact)
    expect(medium).to receive(:address).and_return('johns@example.com')

    expect(alert).to receive(:id).and_return('123456')

    expect(alert).to receive(:medium).exactly(3).times.and_return(medium)

    expect(alert).to receive(:check).exactly(3).times.and_return(check)
    expect(alert).to receive(:state_title_case).exactly(3).times.and_return('OK')
    expect(alert).to receive(:state_duration).twice.and_return(2)
    expect(alert).to receive(:summary).twice.and_return('smile')
    expect(alert).to receive(:details).twice.and_return('')
    expect(alert).to receive(:time).twice.and_return(Time.now)

    expect(alert).to receive(:last_state).twice.and_return( double(Flapjack::Data::CheckState) )
    expect(alert).to receive(:last_state_title_case).twice.and_return('Critical')
    expect(alert).to receive(:last_summary).twice.and_return('frown')

    expect(alert).to receive(:notification_type).and_return('recovery')
    expect(alert).to receive(:type_sentence_case).and_return('Recovery')
    expect(alert).to receive(:rollup).and_return(nil)

    expect(Mail::TestMailer.deliveries).to be_empty

    config = {"smtp_config" => {'from' => 'from@example.org'}}
    email_gw = Flapjack::Gateways::Email.new(:lock => lock, :config => config, :logger => @logger)
    expect { email_gw.start }.to raise_error(Flapjack::PikeletStop)

    expect(Mail::TestMailer.deliveries.size).to eq(1)
  end

end
