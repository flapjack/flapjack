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
      :redis_config => redis_config, :logger => logger).and_return(processor)

    Thread.should_receive(:new).and_yield
    thread.should_receive(:abort_on_exception=).with(true)
    Thread.should_receive(:current).and_return(thread)

    condition.should_receive(:signal)

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
      :redis_config => redis_config, :logger => logger).and_return(processor)

    Thread.should_receive(:new).and_yield
    thread.should_receive(:abort_on_exception=).with(true)
    Thread.should_receive(:current).and_return(thread)

    shutdown.should_receive(:call)

    wrappers = Flapjack::Pikelet.create('processor', shutdown, :config => config,
      :redis_config => redis_config, :logger => logger)
    wrappers.should_not be_nil
    wrappers.should have(1).wrapper
    wrapper = wrappers.first
    wrapper.should be_a(Flapjack::Pikelet::Generic)
    wrapper.should_receive(:new_cond).and_return(condition)
    wrapper.should_receive(:synchronize).and_yield
    wrapper.start
  end

  it "creates and starts a http server gateway" do
    Flapjack::Logger.should_receive(:new).and_return(logger)

    config.should_receive(:[]).with('logger').and_return(nil)
    config.should_receive(:[]).with('max_runs').and_return(nil)
    config.should_receive(:[]).with('port').and_return(7654)
    config.should_receive(:[]).with('timeout').and_return(90)

    server = mock('server')
    server.should_receive(:mount).with('/', Rack::Handler::WEBrick,
      Flapjack::Gateways::Web)
    server.should_receive(:start)
    WEBrick::HTTPServer.should_receive(:new).
      with(:Port => 7654, :BindAddress => '127.0.0.1',
           :AccessLog => [], :Logger => an_instance_of(::WEBrick::Log)).
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

  it "handles an exception from a http server gateway" do
    exc = RuntimeError.new

    Flapjack::Logger.should_receive(:new).and_return(logger)
    logger.should_receive(:warn).twice

    config.should_receive(:[]).with('logger').and_return(nil)
    config.should_receive(:[]).with('max_runs').and_return(nil)
    config.should_receive(:[]).with('port').and_return(7654)
    config.should_receive(:[]).with('timeout').and_return(90)

    server = mock('server')
    server.should_receive(:mount).with('/', Rack::Handler::WEBrick,
      Flapjack::Gateways::Web)
    server.should_receive(:start).and_raise(exc)
    WEBrick::HTTPServer.should_receive(:new).
      with(:Port => 7654, :BindAddress => '127.0.0.1',
           :AccessLog => [], :Logger => an_instance_of(::WEBrick::Log)).
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
