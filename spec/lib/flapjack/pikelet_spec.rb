require 'spec_helper'
require 'flapjack/pikelet'

describe Flapjack::Pikelet do

  let(:config)       { mock('config') }
  let(:redis_config) { mock('redis_config') }

  let(:logger)       { mock(Flapjack::Logger) }

  let(:monitor)      { mock(Monitor) }
  let(:thread)       { mock(Thread) }

  it "creates and starts an executive pikelet" do
    Flapjack::Logger.should_receive(:new).and_return(logger)

    config.should_receive(:[]).with('logger').and_return(nil)

    executive = mock('executive')
    executive.should_receive(:start)
    Flapjack::Executive.should_receive(:new).with(:config => config,
      :redis_config => redis_config, :logger => logger).and_return(executive)

    Thread.should_receive(:new).and_yield
    thread.should_receive(:abort_on_exception=).with(true)
    Thread.should_receive(:current).and_return(thread)

    monitor.should_receive(:synchronize).and_yield
    Monitor.should_receive(:new).and_return(monitor)

    EM.should_receive(:run).and_yield
    EM.should_receive(:synchrony).and_yield
    EM.should_receive(:error_handler)
    EM.should_receive(:stop_event_loop)

    pik = Flapjack::Pikelet.create('executive', :config => config,
      :redis_config => redis_config)
    pik.should be_a(Flapjack::Pikelet::Generic)
    pik.start
  end

  it "handles an exception from an executive pikelet" do
    exc = RuntimeError.new

    Flapjack::Logger.should_receive(:new).and_return(logger)
    logger.should_receive(:warn).twice
    Kernel.should_receive(:raise).with(exc)

    config.should_receive(:[]).with('logger').and_return(nil)

    executive = mock('executive')
    executive.should_receive(:start).and_raise(exc)
    Flapjack::Executive.should_receive(:new).with(:config => config,
      :redis_config => redis_config, :logger => logger).and_return(executive)

    Thread.should_receive(:new).and_yield
    thread.should_receive(:abort_on_exception=).with(true)
    Thread.should_receive(:current).and_return(thread)

    monitor.should_receive(:synchronize).and_yield
    Monitor.should_receive(:new).and_return(monitor)

    EM.should_receive(:run).and_yield
    EM.should_receive(:synchrony).and_yield
    EM.should_receive(:error_handler)
    EM.should_receive(:stop_event_loop)

    pik = Flapjack::Pikelet.create('executive', :config => config,
      :redis_config => redis_config)
    pik.should be_a(Flapjack::Pikelet::Generic)
    pik.start
  end

  it "handles an EventMachine error from an executive pikelet" do
    exc = RuntimeError.new

    Flapjack::Logger.should_receive(:new).and_return(logger)
    logger.should_receive(:warn).twice
    Kernel.should_receive(:raise)

    config.should_receive(:[]).with('logger').and_return(nil)

    Thread.should_receive(:new).and_yield
    thread.should_receive(:abort_on_exception=).with(true)
    Thread.should_receive(:current).and_return(thread)

    monitor.should_receive(:synchronize).and_yield
    Monitor.should_receive(:new).and_return(monitor)

    EM.should_receive(:run).and_yield
    EM.should_receive(:synchrony).and_yield
     # only once in this case, but in the test can't abort the EM.run block easily
    EM.should_receive(:stop_event_loop).at_least(:once)

    executive = mock('executive')
    executive.should_receive(:start).and_return {
      EM.instance_variable_get("@error_handler").call(exc)
    }
    Flapjack::Executive.should_receive(:new).with(:config => config,
      :redis_config => redis_config, :logger => logger).and_return(executive)

    pik = Flapjack::Pikelet.create('executive', :config => config,
      :redis_config => redis_config)
    pik.should be_a(Flapjack::Pikelet::Generic)
    pik.start
  end

  it "creates and starts a resque worker gateway" do
    Flapjack::Pikelet::Resque.class_variable_set(:@@resque_pool, nil)

    Flapjack::Logger.should_receive(:new).and_return(logger)

    config.should_receive(:[]).with('logger').and_return(nil)
    config.should_receive(:[]).with('queue').and_return('email_notif')

    redis = mock('redis')
    Flapjack::RedisPool.should_receive(:new).and_return(redis)
    Resque.should_receive(:redis=).with( redis )

    Flapjack::Gateways::Email.should_receive(:instance_variable_set).
      with('@config', config)
    Flapjack::Gateways::Email.should_receive(:instance_variable_set).
      with('@redis_config', redis_config)
    Flapjack::Gateways::Email.should_receive(:instance_variable_set).
      with('@logger', logger)

    worker = mock('worker')
    worker.should_receive(:work).with(0.1)
    Flapjack::Gateways::Email.should_receive(:start)
    EM::Resque::Worker.should_receive(:new).with('email_notif').and_return(worker)

    Thread.should_receive(:new).and_yield
    thread.should_receive(:abort_on_exception=).with(true)
    Thread.should_receive(:current).and_return(thread)

    monitor.should_receive(:synchronize).and_yield
    Monitor.should_receive(:new).and_return(monitor)

    EM.should_receive(:run).and_yield
    EM.should_receive(:synchrony).and_yield
    EM.should_receive(:error_handler)
    EM.should_receive(:stop_event_loop)

    pik = Flapjack::Pikelet.create('email', :config => config,
      :redis_config => redis_config)
    pik.should be_a(Flapjack::Pikelet::Resque)
    pik.start
  end

  it "handles an exception from an resque worker gateway" do
    Flapjack::Pikelet::Resque.class_variable_set(:@@resque_pool, nil)

    exc = RuntimeError.new

    Flapjack::Logger.should_receive(:new).and_return(logger)
    logger.should_receive(:warn).twice
    Kernel.should_receive(:raise).with(exc)

    config.should_receive(:[]).with('logger').and_return(nil)
    config.should_receive(:[]).with('queue').and_return('email_notif')

    redis = mock('redis')
    Flapjack::RedisPool.should_receive(:new).and_return(redis)
    Resque.should_receive(:redis=).with( redis )

    Flapjack::Gateways::Email.should_receive(:instance_variable_set).
      with('@config', config)
    Flapjack::Gateways::Email.should_receive(:instance_variable_set).
      with('@redis_config', redis_config)
    Flapjack::Gateways::Email.should_receive(:instance_variable_set).
      with('@logger', logger)

    worker = mock('worker')
    worker.should_receive(:work).with(0.1).and_raise(exc)
    Flapjack::Gateways::Email.should_receive(:start)
    EM::Resque::Worker.should_receive(:new).with('email_notif').and_return(worker)

    Thread.should_receive(:new).and_yield
    thread.should_receive(:abort_on_exception=).with(true)
    Thread.should_receive(:current).and_return(thread)

    monitor.should_receive(:synchronize).and_yield
    Monitor.should_receive(:new).and_return(monitor)

    EM.should_receive(:run).and_yield
    EM.should_receive(:synchrony).and_yield
    EM.should_receive(:error_handler)
    EM.should_receive(:stop_event_loop)

    pik = Flapjack::Pikelet.create('email', :config => config,
      :redis_config => redis_config)
    pik.should be_a(Flapjack::Pikelet::Resque)
    pik.start
  end

  it "handles an EventMachine error from an resque worker gateway"

  it "creates and starts a blather server gateway" do
    Flapjack::Logger.should_receive(:new).and_return(logger)

    config.should_receive(:[]).with('logger').and_return(nil)

    jabber = mock('jabber')
    jabber.should_receive(:start)
    Flapjack::Gateways::Jabber.should_receive(:new).with(:config => config,
      :redis_config => redis_config, :logger => logger).and_return(jabber)

    Thread.should_receive(:new).and_yield
    thread.should_receive(:abort_on_exception=).with(true)
    Thread.should_receive(:current).and_return(thread)

    monitor.should_receive(:synchronize).and_yield
    Monitor.should_receive(:new).and_return(monitor)

    EM.should_receive(:run).and_yield
    EM.should_receive(:error_handler)
    EM.should_receive(:stop_event_loop)

    pik = Flapjack::Pikelet.create('jabber', :config => config,
      :redis_config => redis_config)
    pik.should be_a(Flapjack::Pikelet::Blather)
    pik.start
  end

  it "handles an exception from an blather server gateway" do
    exc = RuntimeError.new

    Flapjack::Logger.should_receive(:new).and_return(logger)
    logger.should_receive(:warn).twice
    Kernel.should_receive(:raise).with(exc)

    config.should_receive(:[]).with('logger').and_return(nil)

    jabber = mock('jabber')
    jabber.should_receive(:start).and_raise(exc)
    Flapjack::Gateways::Jabber.should_receive(:new).with(:config => config,
      :redis_config => redis_config, :logger => logger).and_return(jabber)

    Thread.should_receive(:new).and_yield
    thread.should_receive(:abort_on_exception=).with(true)
    Thread.should_receive(:current).and_return(thread)

    monitor.should_receive(:synchronize).and_yield
    Monitor.should_receive(:new).and_return(monitor)

    EM.should_receive(:run).and_yield
    EM.should_receive(:error_handler)
    EM.should_receive(:stop_event_loop)

    pik = Flapjack::Pikelet.create('jabber', :config => config,
      :redis_config => redis_config)
    pik.should be_a(Flapjack::Pikelet::Blather)
    pik.start
  end

  it "handles an EventMachine error from a blather server gateway"

  it "creates a thin server gateway" do
    Flapjack::Logger.should_receive(:new).and_return(logger)

    config.should_receive(:[]).with('logger').and_return(nil)
    config.should_receive(:[]).with('port').and_return(7654)
    config.should_receive(:[]).with('timeout').and_return(90)

    server = mock('server')
    server.should_receive(:timeout=).with(90)
    server.should_receive(:start)
    Thin::Server.should_receive(:new).
      with(/^(?:\d{1,3}\.){3}\d{1,3}$/, 7654,
        Flapjack::Gateways::Web, :signals => false).
      and_return(server)

    Flapjack::Gateways::Web.should_receive(:instance_variable_set).
      with('@config', config)
    Flapjack::Gateways::Web.should_receive(:instance_variable_set).
      with('@redis_config', redis_config)
    Flapjack::Gateways::Web.should_receive(:instance_variable_set).
      with('@logger', logger)

    Thread.should_receive(:new).and_yield
    thread.should_receive(:abort_on_exception=).with(true)
    Thread.should_receive(:current).and_return(thread)

    monitor.should_receive(:synchronize).and_yield
    Monitor.should_receive(:new).and_return(monitor)

    EM.should_receive(:run).and_yield
    EM.should_receive(:error_handler)

    Flapjack::Gateways::Web.should_receive(:start)

    pik = Flapjack::Pikelet.create('web', :config => config,
      :redis_config => redis_config)
    pik.should be_a(Flapjack::Pikelet::Thin)
    pik.start
  end

  it "handles an exception from a thin server gateway" do
    exc = RuntimeError.new

    Flapjack::Logger.should_receive(:new).and_return(logger)
    logger.should_receive(:warn).twice
    Kernel.should_receive(:raise).with(exc)

    config.should_receive(:[]).with('logger').and_return(nil)
    config.should_receive(:[]).with('port').and_return(7654)
    config.should_receive(:[]).with('timeout').and_return(90)

    server = mock('server')
    server.should_receive(:timeout=).with(90)
    server.should_receive(:start).and_raise(exc)
    Thin::Server.should_receive(:new).
      with(/^(?:\d{1,3}\.){3}\d{1,3}$/, 7654,
        Flapjack::Gateways::Web, :signals => false).
      and_return(server)

    Flapjack::Gateways::Web.should_receive(:instance_variable_set).
      with('@config', config)
    Flapjack::Gateways::Web.should_receive(:instance_variable_set).
      with('@redis_config', redis_config)
    Flapjack::Gateways::Web.should_receive(:instance_variable_set).
      with('@logger', logger)

    Thread.should_receive(:new).and_yield
    thread.should_receive(:abort_on_exception=).with(true)
    Thread.should_receive(:current).and_return(thread)

    monitor.should_receive(:synchronize).and_yield
    Monitor.should_receive(:new).and_return(monitor)

    EM.should_receive(:run).and_yield
    EM.should_receive(:error_handler)

    Flapjack::Gateways::Web.should_receive(:start)

    pik = Flapjack::Pikelet.create('web', :config => config,
      :redis_config => redis_config)
    pik.should be_a(Flapjack::Pikelet::Thin)
    pik.start
  end

  it "handles an EventMachine error from a thin server gateway"

end
