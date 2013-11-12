require 'spec_helper'

require 'flapjack/coordinator'

describe Flapjack::Coordinator do

  let(:config) { double(Flapjack::Configuration) }
  let(:logger) { double(Flapjack::Logger) }

  let!(:time)  { Time.now }

  it "starts and stops a pikelet" do
    Flapjack::Logger.should_receive(:new).and_return(logger)

    cfg = {'processor' => {'enabled' => true}}

    config.should_receive(:all).twice.and_return(cfg)

    wrapper = double(Flapjack::ConnectionPool::Wrapper)
    wrapper.should_receive(:pool_shutdown)
    Flapjack::ConnectionPool::Wrapper.should_receive(:new).
      with(hash_including(:size => 2)).and_return(wrapper)

    Flapjack.should_receive(:redis=).with(wrapper)
    Flapjack.should_receive(:redis).and_return(wrapper)

    processor = double('processor')
    processor.should_receive(:start)
    processor.should_receive(:stop)
    processor.should_receive(:redis_connections_required).and_return(1)

    Thread.should_receive(:new).and_yield

    running_cond = double(MonitorMixin::ConditionVariable)
    running_cond.should_receive(:wait)
    running_cond.should_receive(:signal)

    monitor = double(Monitor)
    monitor.should_receive(:synchronize).twice.and_yield
    monitor.should_receive(:new_cond).and_return(running_cond)
    Monitor.should_receive(:new).and_return(monitor)

    Time.should_receive(:now).and_return(time)

    fc = Flapjack::Coordinator.new(config)
    Flapjack::Pikelet.should_receive(:create).with('processor',
        an_instance_of(Proc), :config => cfg['processor'],
        :boot_time => time).
      and_return([processor])

    fc.start(:signals => false)
    fc.stop
  end

  it "loads an old executive pikelet config block with no new data" do
    cfg = {'executive' => {'enabled' => true}}

    config.should_receive(:all).twice.and_return(cfg)

    wrapper = double(Flapjack::ConnectionPool::Wrapper)
    wrapper.should_receive(:pool_shutdown)
    Flapjack::ConnectionPool::Wrapper.should_receive(:new).
      with(hash_including(:size => 3)).and_return(wrapper)

    Flapjack.should_receive(:redis=).with(wrapper)
    Flapjack.should_receive(:redis).and_return(wrapper)

    processor = double('processor')
    processor.should_receive(:start)
    processor.should_receive(:stop)
    processor.should_receive(:redis_connections_required).and_return(1)

    notifier = double('notifier')
    notifier.should_receive(:start)
    notifier.should_receive(:stop)
    notifier.should_receive(:redis_connections_required).and_return(1)

    Thread.should_receive(:new).and_yield

    running_cond = double(MonitorMixin::ConditionVariable)
    running_cond.should_receive(:wait)
    running_cond.should_receive(:signal)

    monitor = double(Monitor)
    monitor.should_receive(:synchronize).twice.and_yield
    monitor.should_receive(:new_cond).and_return(running_cond)
    Monitor.should_receive(:new).and_return(monitor)

    Time.should_receive(:now).and_return(time)

    fc = Flapjack::Coordinator.new(config)
    Flapjack::Pikelet.should_receive(:create).with('processor',
        an_instance_of(Proc), :config => cfg['executive'],
        :boot_time => time).
      and_return([processor])
    Flapjack::Pikelet.should_receive(:create).with('notifier',
        an_instance_of(Proc), :config => cfg['executive'],
        :boot_time => time).
      and_return([notifier])

    fc.start(:signals => false)
    fc.stop
  end

  it "loads an old executive pikelet config block with some new data" do
    cfg = {'executive' => {'enabled' => true},
           'processor' => {'foo' => 'bar'},
           'notifier'  => {'enabled' => false}
          }

    config.should_receive(:all).twice.and_return(cfg)

    wrapper = double(Flapjack::ConnectionPool::Wrapper)
    wrapper.should_receive(:pool_shutdown)
    Flapjack::ConnectionPool::Wrapper.should_receive(:new).
      with(hash_including(:size => 2)).and_return(wrapper)

    Flapjack.should_receive(:redis=).with(wrapper)
    Flapjack.should_receive(:redis).and_return(wrapper)

    processor = double('processor')
    processor.should_receive(:start)
    processor.should_receive(:stop)
    processor.should_receive(:redis_connections_required).and_return(1)

    Thread.should_receive(:new).and_yield

    running_cond = double(MonitorMixin::ConditionVariable)
    running_cond.should_receive(:wait)
    running_cond.should_receive(:signal)

    monitor = double(Monitor)
    monitor.should_receive(:synchronize).twice.and_yield
    monitor.should_receive(:new_cond).and_return(running_cond)
    Monitor.should_receive(:new).and_return(monitor)

    Time.should_receive(:now).and_return(time)

    fc = Flapjack::Coordinator.new(config)
    Flapjack::Pikelet.should_receive(:create).with('processor',
        an_instance_of(Proc), :config => cfg['processor'].merge('enabled' => true),
        :boot_time => time).
      and_return([processor])

    fc.start(:signals => false)
    fc.stop
  end

  it "traps system signals and shuts down" do
    Flapjack::Logger.should_receive(:new).and_return(logger)

    config.should_receive(:all).and_return({})
    RbConfig::CONFIG.should_receive(:[]).with('host_os').and_return('darwin12.0.0')

    Kernel.should_receive(:trap).with('INT').and_yield
    Kernel.should_receive(:trap).with('TERM').and_yield
    Kernel.should_receive(:trap).with('QUIT').and_yield
    Kernel.should_receive(:trap).with('HUP').and_yield

    fc = Flapjack::Coordinator.new(config)
    fc.should_receive(:stop).exactly(3).times
    fc.should_receive(:reload)

    fc.send(:setup_signals)
  end

  it "only traps two system signals on Windows" do
    Flapjack::Logger.should_receive(:new).and_return(logger)

    config.should_receive(:all).and_return({})
    RbConfig::CONFIG.should_receive(:[]).with('host_os').and_return('mswin')

    Kernel.should_receive(:trap).with('INT').and_yield
    Kernel.should_receive(:trap).with('TERM').and_yield
    Kernel.should_not_receive(:trap).with('QUIT')
    Kernel.should_not_receive(:trap).with('HUP')

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
    processor.should_receive(:type).and_return('processor')
    processor.should_receive(:stop)

    jabber = double('jabber')
    Flapjack::Pikelet.should_receive(:create).
      with('jabber', an_instance_of(Proc),
        :config => {"enabled" => true},
        :boot_time => time).
      and_return([jabber])
    jabber.should_receive(:start)
    jabber.should_receive(:redis_connections_required).and_return(1)

    wrapper = double(Flapjack::ConnectionPool::Wrapper)
    wrapper.should_receive(:pool_adjust_size).with(1)
    Flapjack.should_receive(:redis).and_return(wrapper)

    fc = Flapjack::Coordinator.new(config)

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
    processor.should_receive(:redis_connections_required).and_return(1)

    wrapper = double(Flapjack::ConnectionPool::Wrapper)
    wrapper.should_receive(:pool_adjust_size).with(1)
    Flapjack.should_receive(:redis).and_return(wrapper)

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

    new_processor = double('new_processor')
    new_processor.should_receive(:start)
    new_processor.should_receive(:redis_connections_required).and_return(1)

    wrapper = double(Flapjack::ConnectionPool::Wrapper)
    wrapper.should_receive(:pool_adjust_size).with(1)
    Flapjack.should_receive(:redis).and_return(wrapper)

    fc = Flapjack::Coordinator.new(config)

    Flapjack::Pikelet.should_receive(:create).
      with('processor', an_instance_of(Proc),
        :config => new_cfg['processor'],
        :boot_time => time).
      and_return([new_processor])

    fc.instance_variable_set('@boot_time', time)
    fc.instance_variable_set('@pikelets', [processor])
    fc.reload
    fc.instance_variable_get('@pikelets').should == [new_processor]
  end

end
