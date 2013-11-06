require 'spec_helper'

require 'flapjack/coordinator'

describe Flapjack::Coordinator do

  let(:fiber)  { double(Fiber) }
  let(:config) { double(Flapjack::Configuration) }

  let(:logger) { double(Flapjack::Logger) }

  let!(:time)  { Time.now }

  it "starts and stops a pikelet" do
    Flapjack::Logger.should_receive(:new).and_return(logger)

    cfg = {'processor' => {'enabled' => true}}
    EM.should_receive(:synchrony).and_yield
    config.should_receive(:for_redis).and_return({})
    config.should_receive(:all).twice.and_return(cfg)

    processor = double('processor')
    processor.should_receive(:start)
    processor.should_receive(:stop)
    processor.should_receive(:update_status)
    processor.should_receive(:status).exactly(3).times.and_return('stopped')

    Time.should_receive(:now).and_return(time)

    fc = Flapjack::Coordinator.new(config)
    Flapjack::Pikelet.should_receive(:create).with('processor',
        :config => cfg['processor'], :redis_config => {}, :boot_time => time, :coordinator => fc).
      and_return(processor)

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

    cfg = {'processor' => {'enabled' => true}}
    EM.should_receive(:synchrony).and_yield
    config.should_receive(:for_redis).and_return({})
    config.should_receive(:all).twice.and_return(cfg)

    processor = double('processor')
    processor.should_receive(:start).and_raise(RuntimeError)
    processor.should_receive(:stop)
    processor.should_receive(:update_status)
    processor.should_receive(:status).exactly(3).times.and_return('stopped')

    Time.should_receive(:now).and_return(time)

    fc = Flapjack::Coordinator.new(config)
    Flapjack::Pikelet.should_receive(:create).with('processor',
        :config => cfg['processor'], :redis_config => {}, :boot_time => time, :coordinator => fc)
      .and_return(processor)

    fiber.should_receive(:resume)
    Fiber.should_receive(:new).and_yield.and_return(fiber)

    EM.should_receive(:stop)

    # Syslog.should_receive(:opened?).and_return(true)
    # Syslog.should_receive(:close)

    fc.start(:signals => false)
    fc.stop
  end

  it "loads an old executive pikelet config block with no new data" do
    cfg = {'executive' => {'enabled' => true}}
    EM.should_receive(:synchrony).and_yield
    config.should_receive(:for_redis).and_return({})
    config.should_receive(:all).twice.and_return(cfg)

    processor = double('processor')
    processor.should_receive(:start)
    processor.should_receive(:stop)
    processor.should_receive(:update_status)
    processor.should_receive(:status).exactly(3).times.and_return('stopped')

    notifier = double('processor')
    notifier.should_receive(:start)
    notifier.should_receive(:stop)
    notifier.should_receive(:update_status)
    notifier.should_receive(:status).exactly(3).times.and_return('stopped')

    Time.should_receive(:now).and_return(time)

    fc = Flapjack::Coordinator.new(config)
    Flapjack::Pikelet.should_receive(:create).with('processor',
        :config => cfg['executive'], :redis_config => {}, :boot_time => time, :coordinator => fc).
      and_return(processor)
    Flapjack::Pikelet.should_receive(:create).with('notifier',
        :config => cfg['executive'], :redis_config => {}, :boot_time => time, :coordinator => fc).
      and_return(notifier)

    fiber.should_receive(:resume)
    Fiber.should_receive(:new).and_yield.and_return(fiber)

    EM.should_receive(:stop)

    # Syslog.should_receive(:opened?).and_return(true)
    # Syslog.should_receive(:close)

    fc.start(:signals => false)
    fc.stop
  end

  it "loads an old executive pikelet config block with some new data" do
    cfg = {'executive' => {'enabled' => true},
           'processor' => {'foo' => 'bar'},
           'notifier'  => {'enabled' => false}
          }
    EM.should_receive(:synchrony).and_yield
    config.should_receive(:for_redis).and_return({})
    config.should_receive(:all).twice.and_return(cfg)

    processor = double('processor')
    processor.should_receive(:start)
    processor.should_receive(:stop)
    processor.should_receive(:update_status)
    processor.should_receive(:status).exactly(3).times.and_return('stopped')

    Time.should_receive(:now).and_return(time)

    fc = Flapjack::Coordinator.new(config)
    Flapjack::Pikelet.should_receive(:create).with('processor',
        :config => cfg['executive'].merge(cfg['processor']),
        :redis_config => {}, :boot_time => time, :coordinator => fc).
      and_return(processor)

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

    config.should_receive(:all).and_return({})
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

    config.should_receive(:all).and_return({})
    config.should_receive(:for_redis).and_return({})
    fc = Flapjack::Coordinator.new(config)
    fc.should_receive(:stop).twice

    fc.send(:setup_signals)
  end

  it "stops one pikelet and starts another on reload" do
    Flapjack::Logger.should_receive(:new).and_return(logger)

    old_cfg = {'processor' => {'enabled' => true}}
    new_cfg = {'gateways' => {'jabber' => {'enabled' => true}}}

    new_config = double('new_config')
    filename = double('filename')

    config.should_receive(:all).twice.and_return(old_cfg)
    config.should_receive(:filename).and_return(filename)

    Flapjack::Configuration.should_receive(:new).and_return(new_config)
    new_config.should_receive(:load).with(filename)
    new_config.should_receive(:all).and_return(new_cfg)

    processor = double('processor')
    processor.should_receive(:type).twice.and_return('processor')
    processor.should_receive(:stop)
    processor.should_receive(:update_status)
    processor.should_receive(:status).exactly(3).times.and_return('stopped')

    config.should_receive(:for_redis).and_return({})
    fc = Flapjack::Coordinator.new(config)

    jabber = double('jabber')
    Flapjack::Pikelet.should_receive(:create).
      with('jabber', :config => {"enabled" => true}, :redis_config => {},
        :boot_time => time, :coordinator => fc).
      and_return(jabber)
    jabber.should_receive(:start)

    fiber.should_receive(:resume)
    Fiber.should_receive(:new).and_yield.and_return(fiber)

    fc.instance_variable_set('@boot_time', time)
    fc.instance_variable_set('@pikelets', [processor])
    fc.reload
    fc.instance_variable_get('@pikelets').should == [jabber]


  end

  it "reloads a pikelet config without restarting it" do
    Flapjack::Logger.should_receive(:new).and_return(logger)

    old_cfg = {'processor' => {'enabled' => true, 'foo' => 'bar'}}
    new_cfg = {'processor' => {'enabled' => true, 'foo' => 'baz'}}

    new_config = double('new_config')
    filename = double('filename')

    config.should_receive(:all).twice.and_return(old_cfg)
    config.should_receive(:filename).and_return(filename)

    Flapjack::Configuration.should_receive(:new).and_return(new_config)
    new_config.should_receive(:load).with(filename)
    new_config.should_receive(:all).and_return(new_cfg)

    processor = double('processor')
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
    Flapjack::Logger.should_receive(:new).and_return(logger)

    old_cfg = {'processor' => {'enabled' => true, 'foo' => 'bar'}}
    new_cfg = {'processor' => {'enabled' => true, 'baz' => 'qux'}}

    new_config = double('new_config')
    filename = double('filename')

    config.should_receive(:all).twice.and_return(old_cfg)
    config.should_receive(:filename).and_return(filename)

    Flapjack::Configuration.should_receive(:new).and_return(new_config)
    new_config.should_receive(:load).with(filename)
    new_config.should_receive(:all).and_return(new_cfg)

    processor = double('processor')
    processor.should_receive(:type).exactly(5).times.and_return('processor')
    processor.should_receive(:reload).with(new_cfg['processor']).and_return(false)
    processor.should_receive(:stop)
    processor.should_receive(:update_status)
    processor.should_receive(:status).exactly(3).times.and_return('stopped')

    fiber.should_receive(:resume)
    Fiber.should_receive(:new).and_yield.and_return(fiber)

    new_exec = double('new_executive')
    new_exec.should_receive(:start)

    config.should_receive(:for_redis).and_return({})
    fc = Flapjack::Coordinator.new(config)

    Flapjack::Pikelet.should_receive(:create).
      with('processor', :config => new_cfg['processor'], :redis_config => {},
        :boot_time => time, :coordinator => fc).
      and_return(new_exec)

    fc.instance_variable_set('@boot_time', time)
    fc.instance_variable_set('@pikelets', [processor])
    fc.reload
    fc.instance_variable_get('@pikelets').should == [new_exec]
  end

end
