require 'spec_helper'

require 'flapjack/coordinator'

describe Flapjack::Coordinator do

  let(:fiber)  { mock(Fiber) }
  let(:config) { mock(Flapjack::Configuration) }

  it "starts and stops a pikelet" do
    cfg = {'executive' => {'enabled' => 'yes'}}
    EM.should_receive(:synchrony).and_yield
    config.should_receive(:for_redis).and_return({})
    config.should_receive(:all).and_return(cfg)

    executive = mock('executive')
    executive.should_receive(:start)
    executive.should_receive(:stop)
    executive.should_receive(:status).exactly(3).times.and_return('stopped')

    fc = Flapjack::Coordinator.new(config)
    Flapjack::Pikelet.should_receive(:create).with('executive',
        :config => cfg['executive'], :redis_config => {}).and_return(executive)

    EM.should_receive(:stop)

    fc.start(:signals => false)
    fc.stop
  end

  it "traps system signals and shuts down" do
    RbConfig::CONFIG.should_receive(:[]).with('host_os').and_return('darwin12.0.0')

    Kernel.should_receive(:trap).with('INT').and_yield
    Kernel.should_receive(:trap).with('TERM').and_yield
    Kernel.should_receive(:trap).with('QUIT').and_yield

    config.should_receive(:for_redis).and_return({})
    fc = Flapjack::Coordinator.new(config)
    fc.should_receive(:stop).exactly(3).times

    fc.send(:setup_signals)
  end

  it "only traps two system signals on Windows" do
    RbConfig::CONFIG.should_receive(:[]).with('host_os').and_return('mswin')

    Kernel.should_receive(:trap).with('INT').and_yield
    Kernel.should_receive(:trap).with('TERM').and_yield
    Kernel.should_not_receive(:trap).with('QUIT')

    config.should_receive(:for_redis).and_return({})
    fc = Flapjack::Coordinator.new(config)
    fc.should_receive(:stop).twice

    fc.send(:setup_signals)
  end

end