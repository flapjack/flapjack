require 'spec_helper'
require 'flapjack/pikelet'

describe Flapjack::Pikelet do

  let(:config) { mock('config') }
  let(:redis_config) { mock('redis_config') }

  let(:logger) { mock(Flapjack::Logger) }

  let(:condition)    { mock(MonitorMixin::ConditionVariable) }
  let(:thread)       { mock(Thread) }
  let(:shutdown)     { mock(Proc) }

  it "creates and starts a processor pikelet" do
    Flapjack::Logger.should_receive(:new).and_return(logger)

    config.should_receive(:[]).with('logger').and_return(nil)
    config.should_receive(:[]).with('max_runs').and_return(nil)

    processor = mock('processor')
    processor.should_receive(:start)
    Flapjack::Processor.should_receive(:new).with(:config => config,
      :redis_config => redis_config, :logger => logger, :siblings => []).and_return(processor)

    Thread.should_receive(:new).and_yield
    thread.should_receive(:abort_on_exception=).with(true)
    Thread.should_receive(:current).and_return(thread)

    condition.should_receive(:signal)

    EM.should_receive(:synchrony).and_yield
    EM.should_receive(:error_handler)
    EM.should_receive(:reactor_running?).and_return(true)
    EM.should_receive(:stop_event_loop)

    pikelets = Flapjack::Pikelet.create('processor', shutdown, :config => config,
      :redis_config => redis_config, :logger => logger)
    pikelets.should_not be_nil
    pikelets.should have(1).pikelet
    pikelet = pikelets.first
    pikelet.should be_a(Flapjack::Pikelet::Generic)
    pikelet.should_receive(:new_cond).and_return(condition)
    pikelet.should_receive(:synchronize).and_yield
    pikelet.start
  end

  it "handles an exception from a processor pikelet, and restarts it" do
    exc = RuntimeError.new

    Flapjack::Logger.should_receive(:new).and_return(logger)
    logger.should_receive(:warn).exactly(4).times

    config.should_receive(:[]).with('logger').and_return(nil)
    config.should_receive(:[]).with('max_runs').and_return(2)

    processor = mock('processor')
    processor.should_receive(:start).twice.and_raise(exc)
    Flapjack::Processor.should_receive(:new).with(:config => config,
      :redis_config => redis_config, :logger => logger, :siblings => []).twice.and_return(processor)

    Thread.should_receive(:new).and_yield
    thread.should_receive(:abort_on_exception=).with(true)
    Thread.should_receive(:current).and_return(thread)

    shutdown.should_receive(:call)

    EM.should_receive(:synchrony).twice.and_yield
    EM.should_receive(:error_handler)
    EM.should_receive(:reactor_running?).twice.and_return(true)
    EM.should_receive(:stop_event_loop).twice

    pikelets = Flapjack::Pikelet.create('processor', shutdown, :config => config,
      :redis_config => redis_config, :logger => logger)
    pikelets.should_not be_nil
    pikelets.should have(1).pikelet
    pikelet = pikelets.first
    pikelet.should be_a(Flapjack::Pikelet::Generic)
    pikelet.should_receive(:new_cond).and_return(condition)
    pikelet.should_receive(:synchronize).and_yield
    pikelet.start
  end

  it "handles an EventMachine error from a processor pikelet" do
    exc = RuntimeError.new

    Flapjack::Logger.should_receive(:new).and_return(logger)
    logger.should_receive(:warn)

    config.should_receive(:[]).with('logger').and_return(nil)
    config.should_receive(:[]).with('max_runs').and_return(nil)

    Thread.should_receive(:new).and_yield
    thread.should_receive(:abort_on_exception=).with(true)
    Thread.should_receive(:current).and_return(thread)

    shutdown.should_receive(:call)

    EM.should_receive(:synchrony).and_yield
    # really only once for the following two, but and_yield doesn't break
    # control flow like the real code does
    EM.should_receive(:reactor_running?).at_least(:once).and_return(true)
    EM.should_receive(:stop_event_loop).at_least(:once)

    processor = mock('processor')
    processor.should_receive(:start).and_return {
      EM.instance_variable_get("@error_handler").call(exc)
    }
    Flapjack::Processor.should_receive(:new).with(:config => config,
      :redis_config => redis_config, :logger => logger, :siblings => []).and_return(processor)

    pikelets = Flapjack::Pikelet.create('processor', shutdown, :config => config,
      :redis_config => redis_config, :logger => logger)
    pikelets.should_not be_nil
    pikelets.should have(1).pikelet
    pikelet = pikelets.first
    pikelet.should be_a(Flapjack::Pikelet::Generic)
    pikelet.should_receive(:new_cond).and_return(condition)
    pikelet.should_receive(:synchronize).and_yield
    pikelet.start
  end

  it "creates and starts a resque worker gateway" do
    ::Flapjack::Pikelet::Resque.instance_eval { @resque_redis = nil }

    Flapjack::Logger.should_receive(:new).and_return(logger)

    config.should_receive(:[]).with('logger').and_return(nil)
    config.should_receive(:[]).with('max_runs').and_return(nil)
    config.should_receive(:[]).with('queue').and_return('email_notif')

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

    condition.should_receive(:signal)

    EM.should_receive(:run).and_yield
    EM.should_receive(:error_handler)
    EM.should_receive(:reactor_running?).and_return(true)
    EM.should_receive(:stop_event_loop)

    pikelets = Flapjack::Pikelet.create('email', shutdown, :config => config,
      :redis_config => redis_config, :logger => logger)
    pikelets.should_not be_nil
    pikelets.should have(1).pikelet
    pikelet = pikelets.first
    pikelet.should be_a(Flapjack::Pikelet::Resque)
    pikelet.should_receive(:new_cond).and_return(condition)
    pikelet.should_receive(:synchronize).and_yield
    pikelet.start
  end

  it "handles an exception from an resque worker gateway" do
    ::Flapjack::Pikelet::Resque.instance_eval { @resque_redis = nil }

    exc = RuntimeError.new

    Flapjack::Logger.should_receive(:new).and_return(logger)
    logger.should_receive(:warn).twice

    config.should_receive(:[]).with('logger').and_return(nil)
    config.should_receive(:[]).with('queue').and_return('email_notif')
    config.should_receive(:[]).with('max_runs').and_return(nil)

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

    shutdown.should_receive(:call)

    EM.should_receive(:run).and_yield
    EM.should_receive(:error_handler)
    EM.should_receive(:reactor_running?).and_return(true)
    EM.should_receive(:stop_event_loop)

    pikelets = Flapjack::Pikelet.create('email', shutdown, :config => config,
      :redis_config => redis_config, :logger => logger)
    pikelets.should_not be_nil
    pikelets.should have(1).pikelet
    pikelet = pikelets.first
    pikelet.should be_a(Flapjack::Pikelet::Resque)
    pikelet.should_receive(:new_cond).and_return(condition)
    pikelet.should_receive(:synchronize).and_yield
    pikelet.start
  end

  it "handles an EventMachine error from an resque worker gateway" do
    ::Flapjack::Pikelet::Resque.instance_eval { @resque_redis = nil }

    exc = RuntimeError.new

    Flapjack::Logger.should_receive(:new).and_return(logger)
    logger.should_receive(:warn)

    config.should_receive(:[]).with('logger').and_return(nil)
    config.should_receive(:[]).with('queue').and_return('email_notif')
    config.should_receive(:[]).with('max_runs').and_return(nil)

    Flapjack::Gateways::Email.should_receive(:instance_variable_set).
      with('@config', config)
    Flapjack::Gateways::Email.should_receive(:instance_variable_set).
      with('@redis_config', redis_config)
    Flapjack::Gateways::Email.should_receive(:instance_variable_set).
      with('@logger', logger)

    Thread.should_receive(:new).and_yield
    thread.should_receive(:abort_on_exception=).with(true)
    Thread.should_receive(:current).and_return(thread)

    shutdown.should_receive(:call)

    worker = mock('worker')
    worker.should_receive(:work).with(0.1).and_return {
      EM.instance_variable_get("@error_handler").call(exc)
    }
    Flapjack::Gateways::Email.should_receive(:start)
    EM::Resque::Worker.should_receive(:new).with('email_notif').and_return(worker)

    EM.should_receive(:run).and_yield
    EM.should_receive(:reactor_running?).at_least(:once).and_return(true)
    EM.should_receive(:stop_event_loop).at_least(:once)

    pikelets = Flapjack::Pikelet.create('email', shutdown, :config => config,
      :redis_config => redis_config, :logger => logger)
    pikelets.should_not be_nil
    pikelets.should have(1).pikelet
    pikelet = pikelets.first
    pikelet.should be_a(Flapjack::Pikelet::Resque)
    pikelet.should_receive(:new_cond).and_return(condition)
    pikelet.should_receive(:synchronize).and_yield
    pikelet.start
  end

  it "creates and starts a thin server gateway" do
    Flapjack::Logger.should_receive(:new).and_return(logger)

    config.should_receive(:[]).with('logger').and_return(nil)
    config.should_receive(:[]).with('max_runs').and_return(nil)
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

    condition.should_receive(:signal)

    EM.should_receive(:run).and_yield
    EM.should_receive(:error_handler)
    EM.should_receive(:reactor_running?).and_return(true)

    Flapjack::Gateways::Web.should_receive(:start)

    pikelets = Flapjack::Pikelet.create('web', shutdown, :config => config,
      :redis_config => redis_config, :logger => logger)
    pikelets.should_not be_nil
    pikelets.should have(1).pikelet
    pikelet = pikelets.first
    pikelet.should be_a(Flapjack::Pikelet::HTTP)
    pikelet.should_receive(:new_cond).and_return(condition)
    pikelet.should_receive(:synchronize).and_yield
    pikelet.start
  end

  it "handles an exception from a thin server gateway" do
    exc = RuntimeError.new

    Flapjack::Logger.should_receive(:new).and_return(logger)
    logger.should_receive(:warn).twice

    config.should_receive(:[]).with('logger').and_return(nil)
    config.should_receive(:[]).with('max_runs').and_return(nil)
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

    shutdown.should_receive(:call)

    EM.should_receive(:run).and_yield
    EM.should_receive(:error_handler)
    EM.should_receive(:reactor_running?).and_return(true)
    EM.should_receive(:stop_event_loop)

    Flapjack::Gateways::Web.should_receive(:start)

    pikelets = Flapjack::Pikelet.create('web', shutdown, :config => config,
      :redis_config => redis_config, :logger => logger)
    pikelets.should_not be_nil
    pikelets.should have(1).pikelet
    pikelet = pikelets.first
    pikelet.should be_a(Flapjack::Pikelet::HTTP)
    pikelet.should_receive(:new_cond).and_return(condition)
    pikelet.should_receive(:synchronize).and_yield
    pikelet.start
  end

  it "handles an EventMachine error from a thin server gateway" do
    exc = RuntimeError.new

    Flapjack::Logger.should_receive(:new).and_return(logger)
    logger.should_receive(:warn)

    config.should_receive(:[]).with('logger').and_return(nil)
    config.should_receive(:[]).with('max_runs').and_return(nil)
    config.should_receive(:[]).with('port').and_return(7654)
    config.should_receive(:[]).with('timeout').and_return(90)

    server = mock('server')
    server.should_receive(:timeout=).with(90)
    server.should_receive(:start).and_return {
      EM.instance_variable_get("@error_handler").call(exc)
    }
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

    shutdown.should_receive(:call)

    EM.should_receive(:run).and_yield
    EM.should_receive(:reactor_running?).twice.and_return(true)
    EM.should_receive(:stop_event_loop).twice

    Flapjack::Gateways::Web.should_receive(:start)

    pikelets = Flapjack::Pikelet.create('web', shutdown, :config => config,
      :redis_config => redis_config, :logger => logger)
    pikelets.should_not be_nil
    pikelets.should have(1).pikelet
    pikelet = pikelets.first
    pikelet.should be_a(Flapjack::Pikelet::HTTP)
    pikelet.should_receive(:new_cond).and_return(condition)
    pikelet.should_receive(:synchronize).and_yield
    pikelet.start
  end

end
