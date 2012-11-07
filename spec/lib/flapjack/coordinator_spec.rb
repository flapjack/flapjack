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

  let(:redis_config) { {} }

  # leaving actual testing of daemonisation to that class's tests
  it "daemonizes properly" do
    fc = Flapjack::Coordinator.new(config, redis_config)
    fc.should_receive(:daemonize)
    fc.should_not_receive(:build_pikelet)
    fc.start(:daemonize => true, :signals => false)
  end

  it "runs undaemonized" do
    EM.should_receive(:synchrony).and_yield

    fc = Flapjack::Coordinator.new(config, redis_config)
    fc.should_receive(:build_pikelet).exactly(3).times
    fc.start(:daemonize => false, :signals => false)
  end

  it "starts after daemonizing" do
    EM.should_receive(:synchrony).and_yield

    fc = Flapjack::Coordinator.new(config, redis_config)
    fc.should_receive(:build_pikelet).exactly(3).times
    fc.after_daemonize
  end

  it "traps system signals and shuts down" do
    RbConfig::CONFIG.should_receive(:[]).with('host_os').and_return('darwin12.0.0')

    Kernel.should_receive(:trap).with('INT').and_yield
    Kernel.should_receive(:trap).with('TERM').and_yield
    Kernel.should_receive(:trap).with('QUIT').and_yield

    fc = Flapjack::Coordinator.new(config, redis_config)
    fc.should_receive(:stop).exactly(3).times

    fc.send(:setup_signals)
  end

  it "only traps two system signals on Windows" do
    RbConfig::CONFIG.should_receive(:[]).with('host_os').and_return('mswin')

    Kernel.should_receive(:trap).with('INT').and_yield
    Kernel.should_receive(:trap).with('TERM').and_yield
    Kernel.should_not_receive(:trap).with('QUIT')

    fc = Flapjack::Coordinator.new(config, redis_config)
    fc.should_receive(:stop).twice

    fc.send(:setup_signals)
  end

  it "stops its services when closing" do
    fiber_exec = mock('fiber_exec')
    fiber_rsq  = mock('fiber_rsq')

    exec  = mock('executive')
    exec.should_receive(:is_a?).with(Flapjack::GenericPikelet).twice.and_return(true)
    exec.should_receive(:stop)
    exec.should_receive(:add_shutdown_event)
    exec.should_receive(:cleanup)

    email = mock('worker')
    email.should_receive(:is_a?).with(Flapjack::GenericPikelet).twice.and_return(false)
    email.should_receive(:shutdown)
    Flapjack::Notification::Email.should_receive(:cleanup)

    backend = mock('backend')
    backend.should_receive(:size).twice.and_return(1, 0)
    web = mock('web')
    web.should_receive(:is_a?).with(Flapjack::GenericPikelet).twice.and_return(false)
    web.should_receive(:backend).twice.and_return(backend)
    web.should_receive(:stop!)
    Flapjack::Web.should_receive(:cleanup)

    redis = mock('redis')
    redis.should_receive(:quit)
    Redis.should_receive(:new).and_return(redis)

    fiber.should_receive(:resume)
    fiber_stop = mock('fiber_stop')
    fiber_stop.should_receive(:resume)
    Fiber.should_receive(:new).twice.and_yield.and_return(fiber, fiber_stop)

    fiber_exec.should_receive(:alive?).exactly(3).times.and_return(true, true, false)
    fiber_rsq.should_receive(:alive?).exactly(3).and_return(true, false, false)

    EM::Synchrony.should_receive(:sleep)
    EM.should_receive(:stop)

    pikelets = [{:fiber => fiber_exec, :instance => exec, :class => Flapjack::Executive},
                {:fiber => fiber_rsq,  :instance => email, :class => Flapjack::Notification::Email},
                {:instance => web, :class => Flapjack::Web}]

    fc = Flapjack::Coordinator.new(config, redis_config)
    fc.instance_variable_set('@redis_options', {})
    fc.instance_variable_set('@pikelets', pikelets)
    fc.stop
  end

  it "creates an executive pikelet" do
    exec = mock('executive')
    exec.should_receive(:bootstrap)
    Flapjack::Executive.should_receive(:new).and_return(exec)
    exec.should_receive(:is_a?).with(Flapjack::GenericPikelet).and_return(true)
    exec.should_receive(:main)

    fiber.should_receive(:resume)
    Fiber.should_receive(:new).and_yield.and_return(fiber)

    fc = Flapjack::Coordinator.new(config, redis_config)
    fc.send(:build_pikelet, 'executive', {})
    pikelets = fc.instance_variable_get('@pikelets')
    pikelets.should_not be_nil
    pikelets.should be_an(Array)
    pikelets.should have(1).pikelet
    pikelets.first.should == {:fiber => fiber, :class => Flapjack::Executive, :instance => exec}
  end

  it "handles an exception raised by a fiber pikelet" do
    jabber = mock('jabber')
    jabber.should_receive(:bootstrap)
    Flapjack::Jabber.should_receive(:new).and_return(jabber)
    jabber.should_receive(:is_a?).with(Flapjack::GenericPikelet).and_return(true)
    jabber.should_receive(:main).and_raise(RuntimeError)

    fiber.should_receive(:resume)
    Fiber.should_receive(:new).and_yield.and_return(fiber)

    fc = Flapjack::Coordinator.new(config, redis_config)
    fc.should_receive(:stop)
    fc.send(:build_pikelet, 'jabber_gateway', {})
    pikelets = fc.instance_variable_get('@pikelets')
    pikelets.should_not be_nil
    pikelets.should be_an(Array)
    pikelets.should have(1).pikelet
    pikelets.first.should == {:fiber => fiber, :class => Flapjack::Jabber, :instance => jabber}
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

    fc = Flapjack::Coordinator.new(config, redis_config)
    fc.send(:build_pikelet, 'email_notifier', {})
    pikelets = fc.instance_variable_get('@pikelets')
    pikelets.should_not be_nil
    pikelets.should be_an(Array)
    pikelets.should have(1).pikelet
    pikelets.first.should == {:fiber => fiber, :class => Flapjack::Notification::Email,
                              :instance => worker}
  end

  it "creates a thin server pikelet" do
    redis = mock('redis')

    server = mock('server')
    server.should_receive(:start)
    Thin::Server.should_receive(:new).
      with(/^(?:\d{1,3}\.){3}\d{1,3}$/, an_instance_of(Fixnum), Flapjack::Web, :signals => false).
      and_return(server)

    Flapjack::RedisPool.should_receive(:new)

    fc = Flapjack::Coordinator.new(config, redis_config)
    fc.send(:build_pikelet, 'web', {})
    pikelets = fc.instance_variable_get('@pikelets')
    pikelets.should_not be_nil
    pikelets.should be_an(Array)
    pikelets.should have(1).pikelet
    pikelets.first.should == {:class => Flapjack::Web, :instance => server}
  end

  # NB: exceptions are handled directly by the Thin pikelets

end