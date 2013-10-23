require 'spec_helper'
require 'flapjack/pikelet'

describe Flapjack::Pikelet, :logger => true do

  let(:config)        { double('config') }

  let(:lock)          { double(Monitor) }
  let(:stop_cond)     { double(MonitorMixin::ConditionVariable) }
  let(:finished_cond) { double(MonitorMixin::ConditionVariable) }
  let(:thread)        { double(Thread) }
  let(:shutdown)      { double(Proc) }

  it "creates and starts a processor pikelet" do
    Flapjack::Logger.should_receive(:new).and_return(@logger)

    config.should_receive(:[]).with('logger').and_return(nil)
    config.should_receive(:[]).with('max_runs').and_return(nil)

    finished_cond.should_receive(:signal)
    lock.should_receive(:new_cond).twice.and_return(stop_cond, finished_cond)
    lock.should_receive(:synchronize).and_yield
    Monitor.should_receive(:new).and_return(lock)

    processor = double('processor')
    processor.should_receive(:start)
    Flapjack::Processor.should_receive(:new).with(:lock => lock,
      :stop_condition => stop_cond, :config => config,
      :logger => @logger).and_return(processor)

    Thread.should_receive(:new).and_yield.and_return(thread)
    thread.should_receive(:abort_on_exception=).with(true)
    Thread.should_receive(:current).and_return(thread)

    pikelets = Flapjack::Pikelet.create('processor', shutdown, :config => config,
      :logger => @logger)
    pikelets.should_not be_nil
    pikelets.should have(1).pikelet
    pikelet = pikelets.first
    pikelet.should be_a(Flapjack::Pikelet::Generic)

    pikelet.start
  end

  it "handles an exception from a processor pikelet, and restarts it, then shuts down" do
    exc = RuntimeError.new
    Flapjack::Logger.should_receive(:new).and_return(@logger)

    config.should_receive(:[]).with('logger').and_return(nil)
    config.should_receive(:[]).with('max_runs').and_return(2)

    finished_cond.should_receive(:signal)
    lock.should_receive(:new_cond).twice.and_return(stop_cond, finished_cond)
    lock.should_receive(:synchronize).and_yield
    Monitor.should_receive(:new).and_return(lock)

    processor = double('processor')
    processor.should_receive(:start).twice.and_raise(exc)
    Flapjack::Processor.should_receive(:new).with(:lock => lock,
      :stop_condition => stop_cond, :config => config,
      :logger => @logger).and_return(processor)

    Thread.should_receive(:new).and_yield.and_return(thread)
    thread.should_receive(:abort_on_exception=).with(true)
    Thread.should_receive(:current).and_return(thread)

   shutdown.should_receive(:call)

    pikelets = Flapjack::Pikelet.create('processor', shutdown, :config => config,
      :logger => @logger)
    pikelets.should_not be_nil
    pikelets.should have(1).pikelet
    pikelet = pikelets.first
    pikelet.should be_a(Flapjack::Pikelet::Generic)

    pikelet.start
  end

  it "creates and starts a http server gateway" do
    Flapjack::Logger.should_receive(:new).and_return(@logger)

    config.should_receive(:[]).with('logger').and_return(nil)
    config.should_receive(:[]).with('max_runs').and_return(nil)
    config.should_receive(:[]).with('port').and_return(7654)
    config.should_receive(:[]).with('timeout').and_return(90)

    finished_cond.should_receive(:signal)
    lock.should_receive(:new_cond).twice.and_return(stop_cond, finished_cond)
    lock.should_receive(:synchronize).and_yield
    Monitor.should_receive(:new).and_return(lock)

    server = double('server')
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
      with('@logger', @logger)

    Thread.should_receive(:new).and_yield.and_return(thread)
    thread.should_receive(:abort_on_exception=).with(true)
    Thread.should_receive(:current).and_return(thread)

    Flapjack::Gateways::Web.should_receive(:start)

    pikelets = Flapjack::Pikelet.create('web', shutdown, :config => config,
      :logger => @logger)
    pikelets.should_not be_nil
    pikelets.should have(1).pikelet
    pikelet = pikelets.first
    pikelet.should be_a(Flapjack::Pikelet::HTTP)
    pikelet.start
  end

  it "handles an exception from a http server gateway" do
    exc = RuntimeError.new

    Flapjack::Logger.should_receive(:new).and_return(@logger)

    config.should_receive(:[]).with('logger').and_return(nil)
    config.should_receive(:[]).with('max_runs').and_return(nil)
    config.should_receive(:[]).with('port').and_return(7654)
    config.should_receive(:[]).with('timeout').and_return(90)

    finished_cond.should_receive(:signal)
    lock.should_receive(:new_cond).twice.and_return(stop_cond, finished_cond)
    lock.should_receive(:synchronize).and_yield
    Monitor.should_receive(:new).and_return(lock)

    server = double('server')
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
      with('@logger', @logger)

    Thread.should_receive(:new).and_yield.and_return(thread)
    thread.should_receive(:abort_on_exception=).with(true)
    Thread.should_receive(:current).and_return(thread)

    shutdown.should_receive(:call)

    Flapjack::Gateways::Web.should_receive(:start)

    pikelets = Flapjack::Pikelet.create('web', shutdown, :config => config,
      :logger => @logger)
    pikelets.should_not be_nil
    pikelets.should have(1).pikelet
    pikelet = pikelets.first
    pikelet.should be_a(Flapjack::Pikelet::HTTP)
    pikelet.start
  end

end
