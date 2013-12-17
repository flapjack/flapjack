require 'spec_helper'
require 'flapjack/notifier'

describe Flapjack::Notifier, :logger => true do

  let(:redis) { double(::Redis) }

  it "starts up, runs and shuts down" do
    # testing with tainted data
    config = {'default_contact_timezone' => 'Australia/Broken_Hill'.taint}

    allow(Flapjack).to receive(:redis).and_return(redis)

    lock = double(Monitor)
    expect(lock).to receive(:synchronize).and_yield

    notifier = Flapjack::Notifier.new(:lock => lock, :config => config, :logger => @logger)

    expect(Flapjack::Data::Notification).to receive(:foreach_on_queue)
    expect(Flapjack::Data::Notification).to receive(:wait_for_queue).and_raise(Flapjack::PikeletStop)

    expect { notifier.start }.to raise_error(Flapjack::PikeletStop)
  end

end
