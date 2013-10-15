require 'spec_helper'
require 'flapjack/notifier'

describe Flapjack::Notifier, :logger => true do

  let(:redis) { mock(::Redis) }

  it "starts up, runs and shuts down" do
    # testing with tainted data
    config = {'default_contact_timezone' => 'Australia/Broken_Hill'.taint}

    Flapjack.stub(:redis).and_return(redis)

    lock = mock(Monitor)
    lock.should_receive(:synchronize).and_yield

    notifier = Flapjack::Notifier.new(:lock => lock, :config => config, :logger => @logger)

    Flapjack::Data::NotificationR.should_receive(:foreach_on_queue)
    Flapjack::Data::NotificationR.should_receive(:wait_for_queue).and_raise(Flapjack::PikeletStop)

    expect { notifier.start }.to raise_error(Flapjack::PikeletStop)
  end

end
