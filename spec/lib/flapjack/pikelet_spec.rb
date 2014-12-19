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
    expect(config).to receive(:[]).with('max_runs').and_return(nil)

    expect(finished_cond).to receive(:signal)
    expect(lock).to receive(:new_cond).twice.and_return(stop_cond, finished_cond)
    expect(lock).to receive(:synchronize).and_yield
    expect(Monitor).to receive(:new).and_return(lock)

    processor = double('processor')
    expect(processor).to receive(:start)
    expect(Flapjack::Processor).to receive(:new).with(:lock => lock,
      :stop_condition => stop_cond, :config => config).and_return(processor)

    expect(Thread).to receive(:new).and_yield.and_return(thread)

    pikelets = Flapjack::Pikelet.create('processor', shutdown, :config => config)
    expect(pikelets).not_to be_nil
    expect(pikelets.size).to eq(1)
    pikelet = pikelets.first
    expect(pikelet).to be_a(Flapjack::Pikelet::Generic)

    pikelet.start
  end

  it "handles an exception from a processor pikelet, and restarts it, then shuts down" do
    exc = RuntimeError.new
    expect(config).to receive(:[]).with('max_runs').and_return(2)

    expect(finished_cond).to receive(:signal)
    expect(lock).to receive(:new_cond).twice.and_return(stop_cond, finished_cond)
    expect(lock).to receive(:synchronize).and_yield
    expect(Monitor).to receive(:new).and_return(lock)

    processor = double('processor')
    expect(processor).to receive(:start).twice.and_raise(exc)
    expect(Flapjack::Processor).to receive(:new).with(:lock => lock,
      :stop_condition => stop_cond, :config => config).and_return(processor)

    expect(Thread).to receive(:new).and_yield.and_return(thread)

   expect(shutdown).to receive(:call)

    pikelets = Flapjack::Pikelet.create('processor', shutdown, :config => config)
    expect(pikelets).not_to be_nil
    expect(pikelets.size).to eq(1)
    pikelet = pikelets.first
    expect(pikelet).to be_a(Flapjack::Pikelet::Generic)

    pikelet.start
  end

  it "creates and starts a http server gateway" do
    expect(config).to receive(:[]).with('max_runs').and_return(nil)
    expect(config).to receive(:[]).with('port').and_return(7654)
    expect(config).to receive(:[]).with('timeout').and_return(90)

    expect(finished_cond).to receive(:signal)
    expect(lock).to receive(:new_cond).twice.and_return(stop_cond, finished_cond)
    expect(lock).to receive(:synchronize).and_yield
    expect(Monitor).to receive(:new).and_return(lock)

    server = double('server')
    expect(server).to receive(:mount).with('/', Rack::Handler::WEBrick,
      Flapjack::Gateways::Web)
    expect(server).to receive(:start)
    expect(WEBrick::HTTPServer).to receive(:new).
      with(:Port => 7654, :BindAddress => '127.0.0.1',
           :AccessLog => [], :Logger => an_instance_of(::WEBrick::Log)).
      and_return(server)

    expect(Flapjack::Gateways::Web).to receive(:instance_variable_set).
      with('@config', config)

    expect(Thread).to receive(:new).and_yield.and_return(thread)

    expect(Flapjack::Gateways::Web).to receive(:start)

    pikelets = Flapjack::Pikelet.create('web', shutdown, :config => config)
    expect(pikelets).not_to be_nil
    expect(pikelets.size).to eq(1)
    pikelet = pikelets.first
    expect(pikelet).to be_a(Flapjack::Pikelet::HTTP)
    pikelet.start
  end

  it "handles an exception from a http server gateway" do
    exc = RuntimeError.new

    expect(config).to receive(:[]).with('max_runs').and_return(nil)
    expect(config).to receive(:[]).with('port').and_return(7654)
    expect(config).to receive(:[]).with('timeout').and_return(90)

    expect(finished_cond).to receive(:signal)
    expect(lock).to receive(:new_cond).twice.and_return(stop_cond, finished_cond)
    expect(lock).to receive(:synchronize).and_yield
    expect(Monitor).to receive(:new).and_return(lock)

    server = double('server')
    expect(server).to receive(:mount).with('/', Rack::Handler::WEBrick,
      Flapjack::Gateways::Web)
    expect(server).to receive(:start).and_raise(exc)
    expect(WEBrick::HTTPServer).to receive(:new).
      with(:Port => 7654, :BindAddress => '127.0.0.1',
           :AccessLog => [], :Logger => an_instance_of(::WEBrick::Log)).
      and_return(server)

    expect(Flapjack::Gateways::Web).to receive(:instance_variable_set).
      with('@config', config)

    expect(Thread).to receive(:new).and_yield.and_return(thread)

    expect(shutdown).to receive(:call)

    expect(Flapjack::Gateways::Web).to receive(:start)

    pikelets = Flapjack::Pikelet.create('web', shutdown, :config => config)
    expect(pikelets).not_to be_nil
    expect(pikelets.size).to eq(1)
    pikelet = pikelets.first
    expect(pikelet).to be_a(Flapjack::Pikelet::HTTP)
    pikelet.start
  end

end
