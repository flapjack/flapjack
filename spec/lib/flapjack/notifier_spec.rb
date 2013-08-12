require 'spec_helper'
require 'flapjack/notifier'

describe Flapjack::Notifier, :logger => true do

  let(:redis) { mock(::Redis) }

  it "starts up, runs and shuts down" do
    # testing with tainted data
    config = {'default_contact_timezone' => 'Australia/Broken_Hill'.taint}

    ::Redis.should_receive(:new).and_return(redis)
    notifier = Flapjack::Notifier.new(:config => config, :logger => @logger)

    Flapjack::Data::Notification.should_receive(:foreach_on_queue)
    Flapjack::Data::Notification.should_receive(:wait_for_queue).and_raise(Flapjack::PikeletStop)

    expect { notifier.start }.to raise_error(Flapjack::PikeletStop)
  end

end
