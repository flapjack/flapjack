require 'spec_helper'
require 'flapjack/executive'

describe Flapjack::Executive, :redis => true do

  # NB: this is only testing the public API of the Executive class, which is pretty limited.
  # Most test coverage for this class comes from the cucumber features.

  it "is initialised with default settings" do
    t = Time.now.to_i

    Flapjack::Filters::NoPreviousState.should_receive(:new)
    Flapjack::Filters::Ok.should_receive(:new)
    Flapjack::Filters::ScheduledMaintenance.should_receive(:new)
    Flapjack::Filters::UnscheduledMaintenance.should_receive(:new)
    Flapjack::Filters::DetectMassClientFailures.should_receive(:new)
    Flapjack::Filters::Delays.should_receive(:new)
    Flapjack::Filters::Acknowledgement.should_receive(:new)

    executive = Flapjack::Executive.new(:redis => @redis)

    # TODO these will need to be made relative to the running instance,
    # and a list of the running instances maintained somewhere
    boot_time = @redis.get('boot_time')
    boot_time.should_not be_nil
    boot_time.to_i.should >= t

    @redis.hget('event_counters', 'all').should == 0.to_s
    @redis.hget('event_counters', 'ok').should == 0.to_s
    @redis.hget('event_counters', 'failure').should == 0.to_s
    @redis.hget('event_counters', 'action').should == 0.to_s
  end

  it "shuts down when provided with a shutdown event" do
    shutdown_evt = mock(Flapjack::Data::Event)
    shutdown_evt.should_receive(:id).twice.and_return('-:-')
    shutdown_evt.should_receive(:type).twice.and_return('shutdown')
    shutdown_evt.should_receive(:state).and_return(nil)
    shutdown_evt.should_receive(:summary).and_return(nil)
    shutdown_evt.should_receive(:time).and_return(Time.now)
    Flapjack::Data::Event.should_receive(:next).and_return(shutdown_evt)
    @redis.should_receive(:quit)

    executive = Flapjack::Executive.new(:redis => @redis)
    # hacky, but the behaviour it's mimicking (shutdown from another thread) isn't
    # conducive to nice tests
    executive.stub(:should_quit?).and_return(false, true)
    executive.main
  end

end