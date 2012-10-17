require 'spec_helper'
require 'flapjack/coordinator'

describe Flapjack::Coordinator do

  let(:fiber) { mock('Fiber') }

  it "is initialized"

  it "starts a suite of services based on config settings"

  it "runs daemonized"

  it "runs undaemonized"

  it "traps system signals and shuts down"

  it "stops its services when closing"

  it "creates an executive pikelet" do
    exec = mock('executive')
    exec.should_receive(:bootstrap)
    Flapjack::Executive.should_receive(:new).and_return(exec)
    exec.should_receive(:main)

    fiber.should_receive(:resume)
    Fiber.should_receive(:new).and_yield.and_return(fiber)

    fc = Flapjack::Coordinator.new
    fc.send(:build_pikelet, 'executive', {})
    pikelets = fc.instance_variable_get('@pikelets')
    pikelets.should_not be_nil
    pikelets.should be_an(Array)
    pikelets.should have(1).pikelet
    pikelets.first.should == {:fiber => fiber, :type => 'executive', :instance => exec}
  end

  it "handles an exception raised by a jabber pikelet" do
    jabber = mock('jabber')
    jabber.should_receive(:bootstrap)
    Flapjack::Jabber.should_receive(:new).and_return(jabber)
    jabber.should_receive(:main).and_raise(RuntimeError)

    fiber.should_receive(:resume)
    Fiber.should_receive(:new).and_yield.and_return(fiber)

    fc = Flapjack::Coordinator.new
    fc.should_receive(:stop)
    fc.send(:build_pikelet, 'jabber_gateway', {})
    pikelets = fc.instance_variable_get('@pikelets')
    pikelets.should_not be_nil
    pikelets.should be_an(Array)
    pikelets.should have(1).pikelet
    pikelets.first.should == {:fiber => fiber, :type => 'jabber_gateway', :instance => jabber}
  end

  it "creates a resque worker pikelet" do
    redis = mock('redis')
    Flapjack::RedisPool.should_receive(:new).and_return(redis)
    Resque.should_receive(:redis=).with(redis)

    worker = mock('worker')
    EM::Resque::Worker.should_receive(:new).and_return(worker)
    worker.should_receive(:work)

    fiber.should_receive(:resume)
    Fiber.should_receive(:new).and_yield.and_return(fiber)

    fc = Flapjack::Coordinator.new
    fc.send(:build_resque_pikelet, 'email_notifier', {})
    pikelets = fc.instance_variable_get('@pikelets')
    pikelets.should_not be_nil
    pikelets.should be_an(Array)
    pikelets.should have(1).pikelet
    pikelets.first.should == {:fiber => fiber, :type => 'email_notifier', :instance => worker, :pool => redis}
  end

  it "handles an exception raised by a resque worker pikelet"

  it "creates a thin server pikelet" do
    redis = mock('redis')
    Flapjack::RedisPool.should_receive(:new).and_return(redis)

    server = mock('server')
    server.should_receive(:start)
    Thin::Server.should_receive(:new).
      with(/^(?:\d{1,3}\.){3}\d{1,3}$/, an_instance_of(Fixnum), Flapjack::Web, :signals => false).
      and_return(server)

    fc = Flapjack::Coordinator.new
    fc.send(:build_thin_pikelet, 'web', {})
    pikelets = fc.instance_variable_get('@pikelets')
    pikelets.should_not be_nil
    pikelets.should be_an(Array)
    pikelets.should have(1).pikelet
    pikelets.first.should == {:type => 'web', :instance => server, :pool => redis}
  end

  # NB: exceptions are handled directly by the Thin pikelets

end