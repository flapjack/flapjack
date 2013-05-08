require 'spec_helper'

require 'flapjack/coordinator'

describe Flapjack::Coordinator do

  let(:fiber)  { mock(Fiber) }
  let(:config) { mock(Flapjack::Configuration) }

  let(:logger)     { mock(Logger) }
  let(:stdout_out) { mock('stdout_out') }
  let(:syslog_out) { mock('syslog_out') }

  def setup_logger
    formatter = mock('Formatter')
    Log4r::PatternFormatter.should_receive(:new).with(
      :pattern => "%d [%l] :: flapjack-coordinator :: %m",
      :date_pattern => "%Y-%m-%dT%H:%M:%S%z").and_return(formatter)

    stdout_out.should_receive(:formatter=).with(formatter)
    syslog_out.should_receive(:formatter=).with(formatter)

    Log4r::StdoutOutputter.should_receive(:new).and_return(stdout_out)
    Log4r::SyslogOutputter.should_receive(:new).and_return(syslog_out)
    logger.should_receive(:add).with(stdout_out)
    logger.should_receive(:add).with(syslog_out)
    Log4r::Logger.should_receive(:new).and_return(logger)
  end

  it "starts and stops a pikelet" do
    setup_logger

    cfg = {'executive' => {'enabled' => 'yes'}}
    EM.should_receive(:synchrony).and_yield
    config.should_receive(:for_redis).and_return({})
    config.should_receive(:all).and_return(cfg)

    executive = mock('executive')
    executive.should_receive(:start)
    executive.should_receive(:stop)
    executive.should_receive(:update_status)
    executive.should_receive(:status).exactly(3).times.and_return('stopped')

    fc = Flapjack::Coordinator.new(config)
    Flapjack::Pikelet.should_receive(:create).with('executive',
        :config => cfg['executive'], :redis_config => {}).and_return(executive)

    fiber.should_receive(:resume)
    Fiber.should_receive(:new).and_yield.and_return(fiber)

    EM.should_receive(:stop)

    fc.start(:signals => false)
    fc.stop
  end

  it "handles an exception raised by a pikelet and shuts down" do
    setup_logger
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

    fc = Flapjack::Coordinator.new(config)
    Flapjack::Pikelet.should_receive(:create).with('executive',
        :config => cfg['executive'], :redis_config => {}).and_return(executive)

    fiber.should_receive(:resume)
    Fiber.should_receive(:new).and_yield.and_return(fiber)

    EM.should_receive(:stop)

    fc.start(:signals => false)
    fc.stop
  end

  it "traps system signals and shuts down" do
    setup_logger

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
    setup_logger

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
    setup_logger

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
    Flapjack::Pikelet.should_receive(:create).with('jabber',
      :config => {"enabled" => "yes"}, :redis_config => {}).and_return(jabber)
    jabber.should_receive(:start)

    fiber.should_receive(:resume)
    Fiber.should_receive(:new).and_yield.and_return(fiber)

    config.should_receive(:for_redis).and_return({})
    fc = Flapjack::Coordinator.new(config)
    fc.instance_variable_set('@pikelets', [executive])
    fc.reload
    fc.instance_variable_get('@pikelets').should == [jabber]
  end

  it "reloads a pikelet config without restarting it" do
    setup_logger

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
    fc.instance_variable_set('@pikelets', [executive])
    fc.reload
    fc.instance_variable_get('@pikelets').should == [executive]
  end

  it "reloads a pikelet config while restarting it" do
    setup_logger

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
      with('executive', :config => new_cfg['executive'], :redis_config => {}).
      and_return(new_exec)

    config.should_receive(:for_redis).and_return({})
    fc = Flapjack::Coordinator.new(config)
    fc.instance_variable_set('@pikelets', [executive])
    fc.reload
    fc.instance_variable_get('@pikelets').should == [new_exec]
  end

end
