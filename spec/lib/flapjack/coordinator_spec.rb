require 'spec_helper'
require 'flapjack/coordinator'

describe Flapjack::Coordinator do

  let(:config)       { double(Flapjack::Configuration) }
  let(:redis_config) { double('redis_config')}

  let!(:time)  { Time.now }

  it "starts and stops a pikelet" do
    cfg = {'processor' => {'enabled' => true}}

    expect(config).to receive(:all).twice.and_return(cfg)

    expect(config).to receive(:for_redis).and_return(redis_config)
    expect(Flapjack::RedisProxy).to receive(:config=).with(redis_config)

    processor = double('processor')
    expect(processor).to receive(:start)
    expect(processor).to receive(:stop)

    running_cond = double(MonitorMixin::ConditionVariable)
    expect(running_cond).to receive(:signal)

    monitor = double(Monitor)
    expect(monitor).to receive(:synchronize).and_yield
    expect(monitor).to receive(:new_cond).and_return(running_cond)
    expect(Monitor).to receive(:new).and_return(monitor)

    expect(Time).to receive(:now).and_return(time)

    fc = Flapjack::Coordinator.new(config)
    expect(running_cond).to receive(:wait_until) {
      fc.instance_variable_set('@state', :stopping)
    }

    expect(Flapjack::Pikelet).to receive(:create).with('processor',
        an_instance_of(Proc), :config => cfg['processor'],
        :boot_time => time).
      and_return([processor])

    fc.start(:signals => false)
  end

  it "loads an old executive pikelet config block with no new data" do
    cfg = {'executive' => {'enabled' => true}}

    expect(config).to receive(:all).twice.and_return(cfg)

    expect(config).to receive(:for_redis).and_return(redis_config)
    expect(Flapjack::RedisProxy).to receive(:config=).with(redis_config)

    processor = double('processor')
    expect(processor).to receive(:start)
    expect(processor).to receive(:stop)

    notifier = double('notifier')
    expect(notifier).to receive(:start)
    expect(notifier).to receive(:stop)

    running_cond = double(MonitorMixin::ConditionVariable)
    expect(running_cond).to receive(:signal)

    monitor = double(Monitor)
    expect(monitor).to receive(:synchronize).and_yield
    expect(monitor).to receive(:new_cond).and_return(running_cond)
    expect(Monitor).to receive(:new).and_return(monitor)

    expect(Time).to receive(:now).and_return(time)


    fc = Flapjack::Coordinator.new(config)
    expect(running_cond).to receive(:wait_until) {
      fc.instance_variable_set('@state', :stopping)
    }

    expect(Flapjack::Pikelet).to receive(:create).with('processor',
        an_instance_of(Proc), :config => cfg['executive'],
        :boot_time => time).
      and_return([processor])
    expect(Flapjack::Pikelet).to receive(:create).with('notifier',
        an_instance_of(Proc), :config => cfg['executive'],
        :boot_time => time).
      and_return([notifier])

    fc.start(:signals => false)
  end

  it "loads an old executive pikelet config block with some new data" do
    cfg = {'executive' => {'enabled' => true},
           'processor' => {'foo' => 'bar'},
           'notifier'  => {'enabled' => false}
          }

    expect(config).to receive(:all).twice.and_return(cfg)

    expect(config).to receive(:for_redis).and_return(redis_config)
    expect(Flapjack::RedisProxy).to receive(:config=).with(redis_config)

    processor = double('processor')
    expect(processor).to receive(:start)
    expect(processor).to receive(:stop)

    running_cond = double(MonitorMixin::ConditionVariable)
    expect(running_cond).to receive(:signal)

    monitor = double(Monitor)
    expect(monitor).to receive(:synchronize).and_yield
    expect(monitor).to receive(:new_cond).and_return(running_cond)
    expect(Monitor).to receive(:new).and_return(monitor)

    expect(Time).to receive(:now).and_return(time)

    fc = Flapjack::Coordinator.new(config)
    expect(running_cond).to receive(:wait_until) {
      fc.instance_variable_set('@state', :stopping)
    }

    expect(Flapjack::Pikelet).to receive(:create).with('processor',
        an_instance_of(Proc), :config => cfg['processor'].merge('enabled' => true),
        :boot_time => time).
      and_return([processor])

    fc.start(:signals => false)
  end

  it "traps system signals and shuts down" do
    expect(RbConfig::CONFIG).to receive(:[]).with('host_os').and_return('darwin12.0.0')

    expect(config).to receive(:all).and_return({})

    thread = double(Thread)
    expect(thread).to receive(:join).exactly(3).times
    expect(Thread).to receive(:new).exactly(3).times.and_yield.and_return(thread)

    expect(Kernel).to receive(:trap).with('INT').and_yield
    expect(Kernel).to receive(:trap).with('TERM').and_yield
    expect(Kernel).to receive(:trap).with('HUP').and_yield

    shutdown = double('shutdown')
    expect(shutdown).to receive(:call).with(2).once
    expect(shutdown).to receive(:call).with(15).once
    reload = double('reload')
    expect(reload).to receive(:call).once

    fc = Flapjack::Coordinator.new(config)
    fc.instance_variable_set('@shutdown', shutdown)
    fc.instance_variable_set('@reload', reload)

    fc.send(:setup_signals)
  end

  it "only traps two system signals on Windows" do
    expect(RbConfig::CONFIG).to receive(:[]).with('host_os').and_return('mswin')

    expect(config).to receive(:all).and_return({})

    thread = double(Thread)
    expect(thread).to receive(:join).twice
    expect(Thread).to receive(:new).twice.and_yield.and_return(thread)

    expect(Kernel).to receive(:trap).with('INT').and_yield
    expect(Kernel).to receive(:trap).with('TERM').and_yield
    expect(Kernel).not_to receive(:trap).with('HUP')

    shutdown = double('shutdown')
    expect(shutdown).to receive(:call).with(2).once
    expect(shutdown).to receive(:call).with(15).once
    reload = double('reload')

    fc = Flapjack::Coordinator.new(config)
    fc.instance_variable_set('@shutdown', shutdown)
    fc.instance_variable_set('@reload', reload)

    fc.send(:setup_signals)
  end

  it "stops one pikelet and starts another on reload" do
    old_cfg = {'processor' => {'enabled' => true}}
    new_cfg = {'gateways' => {'jabber' => {'enabled' => true}}}

    expect(config).to receive(:all).exactly(3).times.and_return(old_cfg, old_cfg, new_cfg)
    expect(config).to receive(:reload)

    processor = double('processor')
    expect(processor).to receive(:type).and_return('processor')
    expect(processor).to receive(:stop)

    jabber = double('jabber')
    expect(Flapjack::Pikelet).to receive(:create).
      with('jabber', an_instance_of(Proc),
        :config => {"enabled" => true},
        :boot_time => time).
      and_return([jabber])
    expect(jabber).to receive(:start)

    fc = Flapjack::Coordinator.new(config)

    fc.instance_variable_set('@boot_time', time)
    fc.instance_variable_set('@pikelets', [processor])
    fc.send(:reload)
    expect(fc.instance_variable_get('@pikelets')).to eq([jabber])
  end

  it "reloads a pikelet config without restarting it" do
    old_cfg = {'processor' => {'enabled' => true, 'foo' => 'bar'}}
    new_cfg = {'processor' => {'enabled' => true, 'foo' => 'baz'}}

    expect(config).to receive(:all).exactly(3).times.and_return(old_cfg, old_cfg, new_cfg)
    expect(config).to receive(:reload)

    processor = double('processor')
    expect(processor).not_to receive(:start)
    expect(processor).to receive(:type).exactly(3).times.and_return('processor')
    expect(processor).to receive(:reload).with(new_cfg['processor']).and_return(true)
    expect(processor).not_to receive(:stop)

    fc = Flapjack::Coordinator.new(config)
    fc.instance_variable_set('@boot_time', time)
    fc.instance_variable_set('@pikelets', [processor])
    fc.send(:reload)
    expect(fc.instance_variable_get('@pikelets')).to eq([processor])
  end

  it "reloads a pikelet config while restarting it" do
    old_cfg = {'processor' => {'enabled' => true, 'foo' => 'bar'}}
    new_cfg = {'processor' => {'enabled' => true, 'baz' => 'qux'}}

    expect(config).to receive(:all).exactly(3).times.and_return(old_cfg, old_cfg, new_cfg)
    expect(config).to receive(:reload)

    processor = double('processor')
    expect(processor).to receive(:type).exactly(5).times.and_return('processor')
    expect(processor).to receive(:reload).with(new_cfg['processor']).and_return(false)
    expect(processor).to receive(:stop)

    new_processor = double('new_processor')
    expect(new_processor).to receive(:start)

    fc = Flapjack::Coordinator.new(config)

    expect(Flapjack::Pikelet).to receive(:create).
      with('processor', an_instance_of(Proc),
        :config => new_cfg['processor'],
        :boot_time => time).
      and_return([new_processor])

    fc.instance_variable_set('@boot_time', time)
    fc.instance_variable_set('@pikelets', [processor])
    fc.send(:reload)
    expect(fc.instance_variable_get('@pikelets')).to eq([new_processor])
  end

end
