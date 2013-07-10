require 'spec_helper'

require 'flapjack/coordinator'

describe Flapjack::Coordinator do

  let(:fiber)  { mock(Fiber) }
  let(:config) { mock(Flapjack::Configuration) }

  let(:logger)     { mock(Flapjack::Logger) }

  let!(:time)   { Time.now }

  it "starts and stops a pikelet" do
    Flapjack::Logger.should_receive(:new).and_return(logger)

    cfg = {'executive' => {'enabled' => 'yes'}}
    EM.should_receive(:synchrony).and_yield
    config.should_receive(:for_redis).and_return({})
    config.should_receive(:all).and_return(cfg)

    executive = mock('executive')
    executive.should_receive(:start)
    executive.should_receive(:stop)
    executive.should_receive(:update_status)
    executive.should_receive(:status).exactly(3).times.and_return('stopped')

    Time.should_receive(:now).and_return(time)

    fc = Flapjack::Coordinator.new(config)
    Flapjack::Pikelet.should_receive(:create).with('executive',
        :config => cfg['executive'], :redis_config => {}, :boot_time => time).
      and_return(executive)

    fiber.should_receive(:resume)
    Fiber.should_receive(:new).and_yield.and_return(fiber)

    EM.should_receive(:stop)

    # Syslog.should_receive(:opened?).and_return(true)
    # Syslog.should_receive(:close)

    fc.start(:signals => false)
    fc.stop
  end

  it "handles an exception raised by a pikelet and shuts down" do
    Flapjack::Logger.should_receive(:new).and_return(logger)
    logger.should_receive(:fatal)

    cfg = {'executive' => {'enabled' => 'yes'}}
    EM.should_receive(:synchrony).and_yield
    config.should_receive(:for_redis).and_return({})
    config.should_receive(:all).and_return(cfg)

    executive = mock('executive')
    executive.should_receive(:start).and_raise(RuntimeError)
    executive.should_receive(:stop)
    executive.should_receive(:update_status)
    executive.should_receive(:status).exactly(3).times.and_return('stopped')

    Time.should_receive(:now).and_return(time)

    fc = Flapjack::Coordinator.new(config)
    Flapjack::Pikelet.should_receive(:create).with('executive',
        :config => cfg['executive'], :redis_config => {}, :boot_time => time)
      .and_return(executive)

    fiber.should_receive(:resume)
    Fiber.should_receive(:new).and_yield.and_return(fiber)

    EM.should_receive(:stop)

    # Syslog.should_receive(:opened?).and_return(true)
    # Syslog.should_receive(:close)

    fc.start(:signals => false)
    fc.stop
  end

  it "traps system signals and shuts down" do
    Flapjack::Logger.should_receive(:new).and_return(logger)

    RbConfig::CONFIG.should_receive(:[]).with('host_os').and_return('darwin12.0.0')

    Kernel.should_receive(:trap).with('INT').and_yield
    Kernel.should_receive(:trap).with('TERM').and_yield
    Kernel.should_receive(:trap).with('QUIT').and_yield
    Kernel.should_receive(:trap).with('HUP').and_yield

    config.should_receive(:for_redis).and_return({})
    fc = Flapjack::Coordinator.new(config)
    fc.should_receive(:stop).exactly(3).times
    fc.should_receive(:reload)

    fc.send(:setup_signals)
  end

  it "only traps two system signals on Windows" do
    Flapjack::Logger.should_receive(:new).and_return(logger)

    RbConfig::CONFIG.should_receive(:[]).with('host_os').and_return('mswin')

    Kernel.should_receive(:trap).with('INT').and_yield
    Kernel.should_receive(:trap).with('TERM').and_yield
    Kernel.should_not_receive(:trap).with('QUIT')
    Kernel.should_not_receive(:trap).with('HUP')

    config.should_receive(:for_redis).and_return({})
    fc = Flapjack::Coordinator.new(config)
    fc.should_receive(:stop).twice

    fc.send(:setup_signals)
  end

  it "stops one pikelet and starts another on reload" do
    Flapjack::Logger.should_receive(:new).and_return(logger)

    old_cfg = {'executive' => {'enabled' => 'yes'}}
    new_cfg = {'gateways' => {'jabber' => {'enabled' => 'yes'}}}

    new_config = mock('new_config')
    filename = mock('filename')

    config.should_receive(:all).and_return(old_cfg)
    config.should_receive(:filename).and_return(filename)

    Flapjack::Configuration.should_receive(:new).and_return(new_config)
    new_config.should_receive(:load).with(filename)
    new_config.should_receive(:all).and_return(new_cfg)

    executive = mock('executive')
    executive.should_receive(:type).twice.and_return('executive')
    executive.should_receive(:stop)
    executive.should_receive(:update_status)
    executive.should_receive(:status).exactly(3).times.and_return('stopped')

    jabber = mock('jabber')
    Flapjack::Pikelet.should_receive(:create).
      with('jabber', :config => {"enabled" => "yes"}, :redis_config => {},
        :boot_time => time).
      and_return(jabber)
    jabber.should_receive(:start)

    fiber.should_receive(:resume)
    Fiber.should_receive(:new).and_yield.and_return(fiber)

    config.should_receive(:for_redis).and_return({})
    fc = Flapjack::Coordinator.new(config)
    fc.instance_variable_set('@boot_time', time)
    fc.instance_variable_set('@pikelets', [executive])
    fc.reload
    fc.instance_variable_get('@pikelets').should == [jabber]
  end

  it "reloads a pikelet config without restarting it" do
    Flapjack::Logger.should_receive(:new).and_return(logger)

    old_cfg = {'executive' => {'enabled' => 'yes', 'foo' => 'bar'}}
    new_cfg = {'executive' => {'enabled' => 'yes', 'foo' => 'baz'}}

    new_config = mock('new_config')
    filename = mock('filename')

    config.should_receive(:all).and_return(old_cfg)
    config.should_receive(:filename).and_return(filename)

    Flapjack::Configuration.should_receive(:new).and_return(new_config)
    new_config.should_receive(:load).with(filename)
    new_config.should_receive(:all).and_return(new_cfg)

    executive = mock('executive')
    executive.should_not_receive(:start)
    executive.should_receive(:type).exactly(3).times.and_return('executive')
    executive.should_receive(:reload).with(new_cfg['executive']).and_return(true)
    executive.should_not_receive(:stop)

    config.should_receive(:for_redis).and_return({})
    fc = Flapjack::Coordinator.new(config)
    fc.instance_variable_set('@boot_time', time)
    fc.instance_variable_set('@pikelets', [executive])
    fc.reload
    fc.instance_variable_get('@pikelets').should == [executive]
  end

  it "reloads a pikelet config while restarting it" do
    Flapjack::Logger.should_receive(:new).and_return(logger)

    old_cfg = {'executive' => {'enabled' => 'yes', 'foo' => 'bar'}}
    new_cfg = {'executive' => {'enabled' => 'yes', 'baz' => 'qux'}}

    new_config = mock('new_config')
    filename = mock('filename')

    config.should_receive(:all).and_return(old_cfg)
    config.should_receive(:filename).and_return(filename)

    Flapjack::Configuration.should_receive(:new).and_return(new_config)
    new_config.should_receive(:load).with(filename)
    new_config.should_receive(:all).and_return(new_cfg)

    executive = mock('executive')
    executive.should_receive(:type).exactly(5).times.and_return('executive')
    executive.should_receive(:reload).with(new_cfg['executive']).and_return(false)
    executive.should_receive(:stop)
    executive.should_receive(:update_status)
    executive.should_receive(:status).exactly(3).times.and_return('stopped')

    fiber.should_receive(:resume)
    Fiber.should_receive(:new).and_yield.and_return(fiber)

    new_exec = mock('new_executive')
    new_exec.should_receive(:start)

    Flapjack::Pikelet.should_receive(:create).
      with('executive', :config => new_cfg['executive'], :redis_config => {},
        :boot_time => time).
      and_return(new_exec)

    config.should_receive(:for_redis).and_return({})
    fc = Flapjack::Coordinator.new(config)
    fc.instance_variable_set('@boot_time', time)
    fc.instance_variable_set('@pikelets', [executive])
    fc.reload
    fc.instance_variable_get('@pikelets').should == [new_exec]
  end

end
