require 'spec_helper'
require 'flapjack/gateways/email'

describe Flapjack::Gateways::Email, :logger => true do

  let(:redis) { double(::Redis) }

  let(:lock)  { double(Monitor) }

  let(:queue) { double(Flapjack::RecordQueue) }
  let(:alert) { double(Flapjack::Data::Alert) }

  before(:each) do
    Mail::TestMailer.deliveries.clear
  end

  it "sends a mail with text and html parts and custom from address" do
    expect(redis).to receive(:quit)
    allow(Flapjack).to receive(:redis).and_return(redis)

    expect(Flapjack::RecordQueue).to receive(:new).with('email_notifications',
      Flapjack::Data::Alert).and_return(queue)

    expect(lock).to receive(:synchronize).and_yield
    expect(queue).to receive(:foreach).and_yield(alert)
    expect(queue).to receive(:wait).and_raise(Flapjack::PikeletStop)

    check = double(Flapjack::Data::Check)
    expect(check).to receive(:name).exactly(3).times.and_return('example.com:ping')

    contact = double(Flapjack::Data::Contact)
    expect(contact).to receive(:name).twice.and_return('John Smith')

    medium = double(Flapjack::Data::Medium)
    expect(medium).to receive(:contact).twice.and_return(contact)
    expect(medium).to receive(:address).and_return('johns@example.com')

    expect(alert).to receive(:id).and_return('123456')

    expect(alert).to receive(:medium).exactly(3).times.and_return(medium)

    expect(alert).to receive(:check).exactly(3).times.and_return(check)
    expect(alert).to receive(:state_title_case).exactly(3).times.and_return('OK')
    expect(alert).to receive(:condition_duration).twice.and_return(2)
    expect(alert).to receive(:summary).twice.and_return('smile')
    expect(alert).to receive(:details).twice.and_return('')
    expect(alert).to receive(:time).twice.and_return(Time.now)

    expect(alert).to receive(:last_state).twice.and_return( double(Flapjack::Data::State) )
    expect(alert).to receive(:last_state_title_case).twice.and_return('Critical')
    expect(alert).to receive(:last_summary).twice.and_return('frown')

    expect(alert).to receive(:notification_type).and_return('recovery')
    expect(alert).to receive(:type_sentence_case).and_return('Recovery')
    expect(alert).to receive(:rollup).and_return(nil)

    expect(Mail::TestMailer.deliveries).to be_empty

    config = {"smtp_config" => {'from' => 'from@example.org'}}
    email_gw = Flapjack::Gateways::Email.new(:lock => lock, :config => config)
    expect { email_gw.start }.to raise_error(Flapjack::PikeletStop)

    expect(Mail::TestMailer.deliveries.size).to eq(1)
    mail = Mail::TestMailer.deliveries.first
    expect(mail.header['From'].addresses).to eq(['from@example.org'])
  end

  it "can have a full name in custom from email address" do
    expect(redis).to receive(:quit)
    allow(Flapjack).to receive(:redis).and_return(redis)

    expect(Flapjack::RecordQueue).to receive(:new).with('email_notifications',
      Flapjack::Data::Alert).and_return(queue)

    expect(lock).to receive(:synchronize).and_yield
    expect(queue).to receive(:foreach).and_yield(alert)
    expect(queue).to receive(:wait).and_raise(Flapjack::PikeletStop)

    check = double(Flapjack::Data::Check)
    expect(check).to receive(:name).exactly(3).times.and_return('example.com:ping')

    contact = double(Flapjack::Data::Contact)
    expect(contact).to receive(:name).twice.and_return('John Smith')

    medium = double(Flapjack::Data::Medium)
    expect(medium).to receive(:contact).twice.and_return(contact)
    expect(medium).to receive(:address).and_return('johns@example.com')

    expect(alert).to receive(:id).and_return('123456')

    expect(alert).to receive(:medium).exactly(3).times.and_return(medium)

    expect(alert).to receive(:check).exactly(3).times.and_return(check)
    expect(alert).to receive(:state_title_case).exactly(3).times.and_return('OK')
    expect(alert).to receive(:condition_duration).twice.and_return(2)
    expect(alert).to receive(:summary).twice.and_return('smile')
    expect(alert).to receive(:details).twice.and_return('')
    expect(alert).to receive(:time).twice.and_return(Time.now)

    expect(alert).to receive(:last_state).twice.and_return( double(Flapjack::Data::State) )
    expect(alert).to receive(:last_state_title_case).twice.and_return('Critical')
    expect(alert).to receive(:last_summary).twice.and_return('frown')

    expect(alert).to receive(:notification_type).and_return('recovery')
    expect(alert).to receive(:type_sentence_case).and_return('Recovery')
    expect(alert).to receive(:rollup).and_return(nil)

    expect(Mail::TestMailer.deliveries).to be_empty

    config = {"smtp_config" => {'from' => 'Full Name <from@example.org>'}}
    email_gw = Flapjack::Gateways::Email.new(:lock => lock, :config => config)
    expect { email_gw.start }.to raise_error(Flapjack::PikeletStop)

    expect(Mail::TestMailer.deliveries.size).to eq(1)

    mail = Mail::TestMailer.deliveries.first
    expect(mail.header['Reply-To'].display_names).to eq(['Full Name'])
    expect(mail.header['Reply-To'].addresses).to eq(['from@example.org'])
  end

  it "can have a custom reply-to address" do
    expect(redis).to receive(:quit)
    allow(Flapjack).to receive(:redis).and_return(redis)

    expect(Flapjack::RecordQueue).to receive(:new).with('email_notifications',
      Flapjack::Data::Alert).and_return(queue)

    expect(lock).to receive(:synchronize).and_yield
    expect(queue).to receive(:foreach).and_yield(alert)
    expect(queue).to receive(:wait).and_raise(Flapjack::PikeletStop)

    check = double(Flapjack::Data::Check)
    expect(check).to receive(:name).exactly(3).times.and_return('example.com:ping')

    contact = double(Flapjack::Data::Contact)
    expect(contact).to receive(:name).twice.and_return('John Smith')

    medium = double(Flapjack::Data::Medium)
    expect(medium).to receive(:contact).twice.and_return(contact)
    expect(medium).to receive(:address).and_return('johns@example.com')

    expect(alert).to receive(:id).and_return('123456')

    expect(alert).to receive(:medium).exactly(3).times.and_return(medium)

    expect(alert).to receive(:check).exactly(3).times.and_return(check)
    expect(alert).to receive(:state_title_case).exactly(3).times.and_return('OK')
    expect(alert).to receive(:condition_duration).twice.and_return(2)
    expect(alert).to receive(:summary).twice.and_return('smile')
    expect(alert).to receive(:details).twice.and_return('')
    expect(alert).to receive(:time).twice.and_return(Time.now)

    expect(alert).to receive(:last_state).twice.and_return( double(Flapjack::Data::State) )
    expect(alert).to receive(:last_state_title_case).twice.and_return('Critical')
    expect(alert).to receive(:last_summary).twice.and_return('frown')

    expect(alert).to receive(:notification_type).and_return('recovery')
    expect(alert).to receive(:type_sentence_case).and_return('Recovery')
    expect(alert).to receive(:rollup).and_return(nil)

    expect(Mail::TestMailer.deliveries).to be_empty

    config = {"smtp_config" => {'from' => 'from@example.org', 'reply_to' => 'reply-to@example.com'}}
    email_gw = Flapjack::Gateways::Email.new(:lock => lock, :config => config)
    expect { email_gw.start }.to raise_error(Flapjack::PikeletStop)

    expect(Mail::TestMailer.deliveries.size).to eq(1)

    mail = Mail::TestMailer.deliveries.first
    expect(mail.header['From'].addresses).to eq(['from@example.org'])
    expect(mail.header['Reply-To'].addresses).to eq(['reply-to@example.com'])
  end

  it "must default to from address if no reply-to given" do
    expect(redis).to receive(:quit)
    allow(Flapjack).to receive(:redis).and_return(redis)

    expect(Flapjack::RecordQueue).to receive(:new).with('email_notifications',
      Flapjack::Data::Alert).and_return(queue)

    expect(lock).to receive(:synchronize).and_yield
    expect(queue).to receive(:foreach).and_yield(alert)
    expect(queue).to receive(:wait).and_raise(Flapjack::PikeletStop)

    check = double(Flapjack::Data::Check)
    expect(check).to receive(:name).exactly(3).times.and_return('example.com:ping')

    contact = double(Flapjack::Data::Contact)
    expect(contact).to receive(:name).twice.and_return('John Smith')

    medium = double(Flapjack::Data::Medium)
    expect(medium).to receive(:contact).twice.and_return(contact)
    expect(medium).to receive(:address).and_return('johns@example.com')

    expect(alert).to receive(:id).and_return('123456')

    expect(alert).to receive(:medium).exactly(3).times.and_return(medium)

    expect(alert).to receive(:check).exactly(3).times.and_return(check)
    expect(alert).to receive(:state_title_case).exactly(3).times.and_return('OK')
    expect(alert).to receive(:condition_duration).twice.and_return(2)
    expect(alert).to receive(:summary).twice.and_return('smile')
    expect(alert).to receive(:details).twice.and_return('')
    expect(alert).to receive(:time).twice.and_return(Time.now)

    expect(alert).to receive(:last_state).twice.and_return( double(Flapjack::Data::State) )
    expect(alert).to receive(:last_state_title_case).twice.and_return('Critical')
    expect(alert).to receive(:last_summary).twice.and_return('frown')

    expect(alert).to receive(:notification_type).and_return('recovery')
    expect(alert).to receive(:type_sentence_case).and_return('Recovery')
    expect(alert).to receive(:rollup).and_return(nil)

    expect(Mail::TestMailer.deliveries).to be_empty

    config = {"smtp_config" => {'from' => 'from@example.org'}}
    email_gw = Flapjack::Gateways::Email.new(:lock => lock, :config => config)
    expect { email_gw.start }.to raise_error(Flapjack::PikeletStop)

    expect(Mail::TestMailer.deliveries.size).to eq(1)

    mail = Mail::TestMailer.deliveries.first
    expect(mail.header['Reply-To'].addresses).to eq(['from@example.org'])
  end

end
