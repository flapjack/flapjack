require 'spec_helper'
require 'flapjack/gateways/threema'

describe Flapjack::Gateways::Threema, :logger => true do

  let(:lock)  { double(Monitor) }
  let(:redis) { double(Redis)}

  let(:config) { {'from'  => 'user',
                  'secret'  => 'password'
                 }
               }

  let(:time) { Time.new(2013, 10, 31, 13, 45) }
  let(:time_str) { Time.at(time).strftime('%-d %b %H:%M') }

  let(:queue) { double(Flapjack::RecordQueue) }
  let(:alert) { double(Flapjack::Data::Alert) }

  let(:check)  { double(Flapjack::Data::Check) }

  before(:each) do
    allow(Flapjack).to receive(:redis).and_return(redis)
  end

  it "sends a threema message" do
    req = stub_request(:post, "https://msgapi.threema.ch/send_simple").
      with(:body => {'phone' => '555-555555',
                      'from' => 'user',
                      'secret' => 'password',
                      'text' => "Recovery: 'example.com:ping' is OK at #{time_str}, smile"}).
      to_return(:status => 200)

    expect(Flapjack::RecordQueue).to receive(:new).with('threema_notifications',
      Flapjack::Data::Alert).and_return(queue)

    medium = double(Flapjack::Data::Medium)
    expect(medium).to receive(:address).and_return('555-555555')

    expect(alert).to receive(:medium).and_return(medium)

    expect(alert).to receive(:id).twice.and_return('123456789')
    expect(alert).to receive(:rollup).and_return(nil)

    expect(alert).to receive(:type).and_return('recovery')
    expect(alert).to receive(:type_sentence_case).and_return('Recovery')
    expect(alert).to receive(:summary).and_return('smile')

    expect(alert).to receive(:state_title_case).and_return('OK')
    expect(alert).to receive(:time).and_return(time.to_i)

    expect(check).to receive(:name).and_return('example.com:ping')
    expect(alert).to receive(:check).and_return(check)

    expect(lock).to receive(:synchronize).and_yield
    expect(queue).to receive(:foreach).and_yield(alert)
    expect(queue).to receive(:wait).and_raise(Flapjack::PikeletStop)

    expect(redis).to receive(:quit)

    threema_gw = Flapjack::Gateways::Threema.new(:lock => lock,
                                                   :config => config)
    expect { threema_gw.start }.to raise_error(Flapjack::PikeletStop)
    expect(req).to have_been_requested
  end


  it "does not send an Threema message with an invalid config" do
    expect(Flapjack::RecordQueue).to receive(:new).with('threema_notifications',
      Flapjack::Data::Alert).and_return(queue)

    medium = double(Flapjack::Data::Medium)
    expect(medium).to receive(:address).and_return('555-555555')

    expect(alert).to receive(:medium).and_return(medium)

    expect(alert).to receive(:id).and_return('123456789')
    expect(alert).to receive(:rollup).and_return(nil)

    expect(alert).to receive(:type).and_return('recovery')
    expect(alert).to receive(:type_sentence_case).and_return('Recovery')
    expect(alert).to receive(:summary).and_return('smile')

    expect(alert).to receive(:state_title_case).and_return('OK')
    expect(alert).to receive(:time).and_return(time.to_i)

    expect(check).to receive(:name).and_return('example.com:ping')
    expect(alert).to receive(:check).and_return(check)

    expect(lock).to receive(:synchronize).and_yield
    expect(queue).to receive(:foreach).and_yield(alert)
    expect(queue).to receive(:wait).and_raise(Flapjack::PikeletStop)

    expect(redis).to receive(:quit)

    threema_gw = Flapjack::Gateways::Threema.new(:lock => lock,
                                                   :config => config.reject {|k, v| k == 'secret'})
    expect { threema_gw.start }.to raise_error(Flapjack::PikeletStop)

    expect(WebMock).not_to have_requested(:post,
                                      "https://msgapi.threema.ch/send_simple")
  end

end
