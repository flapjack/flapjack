require 'spec_helper'
require 'flapjack/notifier'

describe Flapjack::Notifier, :logger => true do

  let(:redis) { double(::Redis) }

  it "starts up, runs and shuts down" do
    # testing with tainted data
    config = {'default_contact_timezone' => 'Australia/Broken_Hill'.taint}

    lock = double(Monitor)
    lock.should_receive(:synchronize).and_yield

    notifier = Flapjack::Notifier.new(:lock => lock, :config => config, :logger => @logger)

    redis.should_receive(:rpop).with('notifications').and_return("}", nil)
    redis.should_receive(:quit)
    redis.should_receive(:brpop).with('notifications_actions').and_raise(Flapjack::PikeletStop)
    Flapjack.stub(:redis).and_return(redis)

    expect { notifier.start }.to raise_error(Flapjack::PikeletStop)
  end

end
