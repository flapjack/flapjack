require 'spec_helper'
require 'flapjack/coordinator'

describe Flapjack::Coordinator do

  let(:fiber) { mock('Fiber') }

  let(:config) {
    {'redis'          => {},
     'executive'      => {'enabled' => 'yes'},
     'email_notifier' => {'enabled' => 'yes'},
     'web'            => {'enabled' => 'yes'}
    }
  }

  # leaving actual testing of daemonisation to that class's tests
  it "daemonizes properly" do
    fc = Flapjack::Coordinator.new(config)
    fc.should_receive(:daemonize)
    fc.should_not_receive(:build_pikelet)
    fc.should_not_receive(:build_resque_pikelet)
    fc.should_not_receive(:build_thin_pikelet)
    fc.start(:daemonize => true, :signals => false)
  end

  it "runs undaemonized" do
    EM.should_receive(:synchrony).and_yield

    fc = Flapjack::Coordinator.new(config)
    fc.should_receive(:build_pikelet)
    fc.should_receive(:build_resque_pikelet)
    fc.should_receive(:build_thin_pikelet)
    fc.start(:daemonize => false, :signals => false)
  end

  it "starts after daemonizing" do
    EM.should_receive(:synchrony).and_yield

    fc = Flapjack::Coordinator.new(config)
    fc.should_receive(:build_pikelet)
    fc.should_receive(:build_resque_pikelet)
    fc.should_receive(:build_thin_pikelet)
    fc.after_daemonize
  end

  it "traps system signals and shuts down"

  # TODO whem merged with other changes, this will check pik[:class] instead,
  # having to create instances of the pikelet classes is messy
  it "stops its services when closing" do
    fiber_exec = mock('fiber_exec')
    fiber_rsq  = mock('fiber_rsq')

    exec  = Flapjack::Executive.new
    exec.should_receive(:add_shutdown_event)
    email = EM::Resque::Worker.new('example')
    email.should_receive(:shutdown)

    web   = Thin::Server.new('0.0.0.0', 3000, Flapjack::Web, :signals => false)
    web.should_receive(:stop!)

    redis = mock('redis')
    redis.should_receive(:quit)
    Redis.should_receive(:new).and_return(redis)

    fiber.should_receive(:resume)
    fiber_stop = mock('fiber_stop')
    fiber_stop.should_receive(:resume)
    Fiber.should_receive(:new).twice.and_yield.and_return(fiber, fiber_stop)

    fiber_exec.should_receive(:alive?).and_return(true, false)
    fiber_rsq.should_receive(:alive?).and_return(true, false)

    # EM::Synchrony.should_receive(:sleep)
    EM.should_receive(:stop)

    pikelets = [{:fiber => fiber_exec, :instance => exec},
                {:fiber => fiber_rsq,  :instance => email},
                {:instance => web}]

    fc = Flapjack::Coordinator.new
    fc.instance_variable_set('@redis_options', {})
    fc.instance_variable_set('@pikelets', pikelets)
    fc.stop
  end

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