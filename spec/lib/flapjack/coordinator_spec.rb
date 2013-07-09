require 'spec_helper'

require 'flapjack/coordinator'

describe Flapjack::Coordinator do

  let(:fiber)  { mock(Fiber) }
  let(:config) { mock(Flapjack::Configuration) }

  let(:logger)     { mock(Logger) }
  let(:stdout_out) { mock('stdout_out') }
  let(:syslog_out) { mock('syslog_out') }

  let!(:time)   { Time.now }

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

    cfg = {'processor' => {'enabled' => 'yes'}}
    EM.should_receive(:synchrony).and_yield
    config.should_receive(:for_redis).and_return({})
    config.should_receive(:all).and_return(cfg)

    processor = mock('processor')
    processor.should_receive(:start)
    processor.should_receive(:stop)
    processor.should_receive(:update_status)
    processor.should_receive(:status).exactly(3).times.and_return('stopped')

    Time.should_receive(:now).and_return(time)

    fc = Flapjack::Coordinator.new(config)
    Flapjack::Pikelet.should_receive(:create).with('processor',
        :config => cfg['processor'], :redis_config => {}, :boot_time => time).
      and_return(processor)

    fiber.should_receive(:resume)
    Fiber.should_receive(:new).and_yield.and_return(fiber)

    EM.should_receive(:stop)

    fc.start(:signals => false)
    fc.stop
  end

  it "handles an exception raised by a pikelet and shuts down" do
    setup_logger
    logger.should_receive(:fatal)

    cfg = {'processor' => {'enabled' => 'yes'}}
    EM.should_receive(:synchrony).and_yield
    config.should_receive(:for_redis).and_return({})
    config.should_receive(:all).and_return(cfg)

    processor = mock('processor')
    processor.should_receive(:start).and_raise(RuntimeError)
    processor.should_receive(:stop)
    processor.should_receive(:update_status)
    processor.should_receive(:status).exactly(3).times.and_return('stopped')

    Time.should_receive(:now).and_return(time)

    fc = Flapjack::Coordinator.new(config)
    Flapjack::Pikelet.should_receive(:create).with('processor',
        :config => cfg['processor'], :redis_config => {}, :boot_time => time)
      .and_return(processor)

    fiber.should_receive(:resume)
    Fiber.should_receive(:new).and_yield.and_return(fiber)

    EM.should_receive(:stop)

    fc.start(:signals => false)
    fc.stop
  end

  it "loads an old executive pikelet config block with no new data" do
    setup_logger

    cfg = {'executive' => {'enabled' => 'yes'}}
    EM.should_receive(:synchrony).and_yield
    config.should_receive(:for_redis).and_return({})
    config.should_receive(:all).and_return(cfg)

    processor = mock('processor')
    processor.should_receive(:start)
    processor.should_receive(:stop)
    processor.should_receive(:update_status)
    processor.should_receive(:status).exactly(3).times.and_return('stopped')

    notifier = mock('processor')
    notifier.should_receive(:start)
    notifier.should_receive(:stop)
    notifier.should_receive(:update_status)
    notifier.should_receive(:status).exactly(3).times.and_return('stopped')

    Time.should_receive(:now).and_return(time)

    fc = Flapjack::Coordinator.new(config)
    Flapjack::Pikelet.should_receive(:create).with('processor',
        :config => cfg['executive'], :redis_config => {}, :boot_time => time).
      and_return(processor)
    Flapjack::Pikelet.should_receive(:create).with('notifier',
        :config => cfg['executive'], :redis_config => {}, :boot_time => time).
      and_return(notifier)

    fiber.should_receive(:resume)
    Fiber.should_receive(:new).and_yield.and_return(fiber)

    EM.should_receive(:stop)

    fc.start(:signals => false)
    fc.stop
  end

  it "loads an old executive pikelet config block with some new data" do
    setup_logger

    cfg = {'executive' => {'enabled' => 'yes'},
           'processor' => {'foo' => 'bar'},
           'notifier'  => {'enabled' => 'no'}
          }
    EM.should_receive(:synchrony).and_yield
    config.should_receive(:for_redis).and_return({})
    config.should_receive(:all).and_return(cfg)

    processor = mock('processor')
    processor.should_receive(:start)
    processor.should_receive(:stop)
    processor.should_receive(:update_status)
    processor.should_receive(:status).exactly(3).times.and_return('stopped')

    Time.should_receive(:now).and_return(time)

    fc = Flapjack::Coordinator.new(config)
    Flapjack::Pikelet.should_receive(:create).with('processor',
        :config => cfg['executive'].merge(cfg['processor']),
        :redis_config => {}, :boot_time => time).
      and_return(processor)

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

    old_cfg = {'processor' => {'enabled' => 'yes'}}
    new_cfg = {'gateways' => {'jabber' => {'enabled' => 'yes'}}}

    new_config = mock('new_config')
    filename = mock('filename')

    config.should_receive(:all).and_return(old_cfg)
    config.should_receive(:filename).and_return(filename)

    Flapjack::Configuration.should_receive(:new).and_return(new_config)
    new_config.should_receive(:load).with(filename)
    new_config.should_receive(:all).and_return(new_cfg)

    processor = mock('processor')
    processor.should_receive(:type).twice.and_return('processor')
    processor.should_receive(:stop)
    processor.should_receive(:update_status)
    processor.should_receive(:status).exactly(3).times.and_return('stopped')

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
    fc.instance_variable_set('@pikelets', [processor])
    fc.reload
    fc.instance_variable_get('@pikelets').should == [jabber]
  end

  it "reloads a pikelet config without restarting it" do
    setup_logger

    old_cfg = {'processor' => {'enabled' => 'yes', 'foo' => 'bar'}}
    new_cfg = {'processor' => {'enabled' => 'yes', 'foo' => 'baz'}}

    new_config = mock('new_config')
    filename = mock('filename')

    config.should_receive(:all).and_return(old_cfg)
    config.should_receive(:filename).and_return(filename)

    Flapjack::Configuration.should_receive(:new).and_return(new_config)
    new_config.should_receive(:load).with(filename)
    new_config.should_receive(:all).and_return(new_cfg)

    processor = mock('processor')
    processor.should_not_receive(:start)
    processor.should_receive(:type).exactly(3).times.and_return('processor')
    processor.should_receive(:reload).with(new_cfg['processor']).and_return(true)
    processor.should_not_receive(:stop)

    config.should_receive(:for_redis).and_return({})
    fc = Flapjack::Coordinator.new(config)
    fc.instance_variable_set('@boot_time', time)
    fc.instance_variable_set('@pikelets', [processor])
    fc.reload
    fc.instance_variable_get('@pikelets').should == [processor]
  end

  it "reloads a pikelet config while restarting it" do
    setup_logger

    old_cfg = {'processor' => {'enabled' => 'yes', 'foo' => 'bar'}}
    new_cfg = {'processor' => {'enabled' => 'yes', 'baz' => 'qux'}}

    new_config = mock('new_config')
    filename = mock('filename')

    config.should_receive(:all).and_return(old_cfg)
    config.should_receive(:filename).and_return(filename)

    Flapjack::Configuration.should_receive(:new).and_return(new_config)
    new_config.should_receive(:load).with(filename)
    new_config.should_receive(:all).and_return(new_cfg)

    processor = mock('processor')
    processor.should_receive(:type).exactly(5).times.and_return('processor')
    processor.should_receive(:reload).with(new_cfg['processor']).and_return(false)
    processor.should_receive(:stop)
    processor.should_receive(:update_status)
    processor.should_receive(:status).exactly(3).times.and_return('stopped')

    fiber.should_receive(:resume)
    Fiber.should_receive(:new).and_yield.and_return(fiber)

    new_exec = mock('new_executive')
    new_exec.should_receive(:start)

    Flapjack::Pikelet.should_receive(:create).
      with('processor', :config => new_cfg['processor'], :redis_config => {},
        :boot_time => time).
      and_return(new_exec)

    config.should_receive(:for_redis).and_return({})
    fc = Flapjack::Coordinator.new(config)
    fc.instance_variable_set('@boot_time', time)
    fc.instance_variable_set('@pikelets', [processor])
    fc.reload
    fc.instance_variable_get('@pikelets').should == [new_exec]
  end

end
