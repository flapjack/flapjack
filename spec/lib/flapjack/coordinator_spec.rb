require 'spec_helper'

require 'flapjack/coordinator'

describe Flapjack::Coordinator do

  let(:fiber)  { double(Fiber) }
  let(:config) { double(Flapjack::Configuration) }

  let(:logger) { double(Flapjack::Logger) }

  let(:redis)  { double(::Redis) }

  let!(:time)  { Time.now }

  it "starts and stops a pikelet" do
    expect(Flapjack::Logger).to receive(:new).and_return(logger)

    cfg = {'processor' => {'enabled' => true}}
    expect(EM).to receive(:synchrony).and_yield
    expect(config).to receive(:for_redis).and_return({})
    expect(config).to receive(:all).twice.and_return(cfg)

    expect(redis).to receive(:keys).with('entity_tag:*').and_return([])
    expect(redis).to receive(:keys).with('check_tag:*').and_return([])
    expect(Flapjack::RedisPool).to receive(:new).and_return(redis)

    processor = double('processor')
    expect(processor).to receive(:start)
    expect(processor).to receive(:stop)
    expect(processor).to receive(:update_status)
    expect(processor).to receive(:status).exactly(3).times.and_return('stopped')

    expect(Time).to receive(:now).and_return(time)

    fc = Flapjack::Coordinator.new(config)
    expect(Flapjack::Pikelet).to receive(:create).with('processor',
        :config => cfg['processor'], :redis_config => {}, :boot_time => time).
      and_return(processor)

    expect(EM).to receive(:stop)
    expect(EM::Synchrony).to receive(:sleep) {
      fc.instance_variable_set('@received_signals', ['INT'])
    }

    expect(Syslog).to receive(:opened?).and_return(true)
    expect(Syslog).to receive(:close)

    fc.start(:signals => false)
  end

  it "handles an exception raised by a pikelet and shuts down" do
    expect(Flapjack::Logger).to receive(:new).and_return(logger)
    expect(logger).to receive(:fatal)

    cfg = {'processor' => {'enabled' => true}}
    expect(EM).to receive(:synchrony).and_yield
    expect(config).to receive(:for_redis).and_return({})
    expect(config).to receive(:all).twice.and_return(cfg)

    expect(redis).to receive(:keys).with('entity_tag:*').and_return([])
    expect(redis).to receive(:keys).with('check_tag:*').and_return([])
    expect(Flapjack::RedisPool).to receive(:new).and_return(redis)

    processor = double('processor')
    expect(processor).to receive(:start).and_raise(RuntimeError)
    expect(processor).to receive(:stop)
    expect(processor).to receive(:update_status)
    expect(processor).to receive(:status).exactly(3).times.and_return('stopped')

    expect(Time).to receive(:now).and_return(time)

    fc = Flapjack::Coordinator.new(config)
    expect(Flapjack::Pikelet).to receive(:create).with('processor',
        :config => cfg['processor'], :redis_config => {}, :boot_time => time)
      .and_return(processor)

    expect(EM).to receive(:stop)

    expect(Syslog).to receive(:opened?).and_return(true)
    expect(Syslog).to receive(:close)

    fc.start(:signals => false)
  end

  it "loads an old executive pikelet config block with no new data" do
    cfg = {'executive' => {'enabled' => true}}
    expect(EM).to receive(:synchrony).and_yield
    expect(config).to receive(:for_redis).and_return({})
    expect(config).to receive(:all).twice.and_return(cfg)

    expect(redis).to receive(:keys).with('entity_tag:*').and_return([])
    expect(redis).to receive(:keys).with('check_tag:*').and_return([])
    expect(Flapjack::RedisPool).to receive(:new).and_return(redis)

    processor = double('processor')
    expect(processor).to receive(:start)
    expect(processor).to receive(:stop)
    expect(processor).to receive(:update_status)
    expect(processor).to receive(:status).exactly(3).times.and_return('stopped')

    notifier = double('processor')
    expect(notifier).to receive(:start)
    expect(notifier).to receive(:stop)
    expect(notifier).to receive(:update_status)
    expect(notifier).to receive(:status).exactly(3).times.and_return('stopped')

    expect(Time).to receive(:now).and_return(time)

    fc = Flapjack::Coordinator.new(config)
    expect(Flapjack::Pikelet).to receive(:create).with('processor',
        :config => cfg['executive'], :redis_config => {}, :boot_time => time).
      and_return(processor)
    expect(Flapjack::Pikelet).to receive(:create).with('notifier',
        :config => cfg['executive'], :redis_config => {}, :boot_time => time).
      and_return(notifier)

    expect(EM).to receive(:stop)
    expect(EM::Synchrony).to receive(:sleep) {
      fc.instance_variable_set('@received_signals', ['INT'])
    }

    expect(Syslog).to receive(:opened?).and_return(true)
    expect(Syslog).to receive(:close)

    fc.start(:signals => false)
  end

  it "loads an old executive pikelet config block with some new data" do
    cfg = {'executive' => {'enabled' => true},
           'processor' => {'foo' => 'bar'},
           'notifier'  => {'enabled' => false}
          }
    expect(EM).to receive(:synchrony).and_yield
    expect(config).to receive(:for_redis).and_return({})
    expect(config).to receive(:all).twice.and_return(cfg)

    expect(redis).to receive(:keys).with('entity_tag:*').and_return([])
    expect(redis).to receive(:keys).with('check_tag:*').and_return([])
    expect(Flapjack::RedisPool).to receive(:new).and_return(redis)

    processor = double('processor')
    expect(processor).to receive(:start)
    expect(processor).to receive(:stop)
    expect(processor).to receive(:update_status)
    expect(processor).to receive(:status).exactly(3).times.and_return('stopped')

    expect(Time).to receive(:now).and_return(time)

    fc = Flapjack::Coordinator.new(config)
    expect(Flapjack::Pikelet).to receive(:create).with('processor',
        :config => cfg['executive'].merge(cfg['processor']),
        :redis_config => {}, :boot_time => time).
      and_return(processor)

    expect(EM).to receive(:stop)
    expect(EM::Synchrony).to receive(:sleep) {
      fc.instance_variable_set('@received_signals', ['INT'])
    }

    expect(Syslog).to receive(:opened?).and_return(true)
    expect(Syslog).to receive(:close)

    fc.start(:signals => false)
  end

  it "traps system signals and shuts down" do
    expect(Flapjack::Logger).to receive(:new).and_return(logger)

    expect(RbConfig::CONFIG).to receive(:[]).with('host_os').and_return('darwin12.0.0')

    expect(Kernel).to receive(:trap).with('INT').and_yield
    expect(Kernel).to receive(:trap).with('TERM').and_yield
    expect(Kernel).to receive(:trap).with('QUIT').and_yield
    expect(Kernel).to receive(:trap).with('HUP').and_yield

    expect(config).to receive(:all).and_return({})
    expect(config).to receive(:for_redis).and_return({})
    fc = Flapjack::Coordinator.new(config)

    fc.send(:setup_signals)
    expect(fc.instance_variable_get('@received_signals')).to eq(['INT', 'TERM', 'QUIT', 'HUP'])
  end

  it "only traps two system signals on Windows" do
    expect(Flapjack::Logger).to receive(:new).and_return(logger)

    expect(RbConfig::CONFIG).to receive(:[]).with('host_os').and_return('mswin')

    expect(Kernel).to receive(:trap).with('INT').and_yield
    expect(Kernel).to receive(:trap).with('TERM').and_yield
    expect(Kernel).not_to receive(:trap).with('QUIT')
    expect(Kernel).not_to receive(:trap).with('HUP')

    expect(config).to receive(:all).and_return({})
    expect(config).to receive(:for_redis).and_return({})
    fc = Flapjack::Coordinator.new(config)

    fc.send(:setup_signals)
    expect(fc.instance_variable_get('@received_signals')).to eq(['INT', 'TERM'])
  end

  it "stops one pikelet and starts another on reload" do
    expect(Flapjack::Logger).to receive(:new).and_return(logger)

    old_cfg = {'processor' => {'enabled' => true}}
    new_cfg = {'gateways' => {'jabber' => {'enabled' => true}}}

    new_config = double('new_config')
    filename = double('filename')

    expect(config).to receive(:all).twice.and_return(old_cfg)
    expect(config).to receive(:filename).and_return(filename)

    expect(Flapjack::Configuration).to receive(:new).and_return(new_config)
    expect(new_config).to receive(:load).with(filename)
    expect(new_config).to receive(:all).and_return(new_cfg)

    processor = double('processor')
    expect(processor).to receive(:type).twice.and_return('processor')
    expect(processor).to receive(:stop)
    expect(processor).to receive(:update_status)
    expect(processor).to receive(:status).exactly(3).times.and_return('stopped')

    expect(config).to receive(:for_redis).and_return({})
    fc = Flapjack::Coordinator.new(config)

    jabber = double('jabber')
    expect(Flapjack::Pikelet).to receive(:create).
      with('jabber', :config => {"enabled" => true}, :redis_config => {},
        :boot_time => time).
      and_return(jabber)
    expect(jabber).to receive(:start)

    fc.instance_variable_set('@boot_time', time)
    fc.instance_variable_set('@pikelets', [processor])
    fc.send(:reload)
    expect(fc.instance_variable_get('@pikelets')).to eq([jabber])
  end

  it "reloads a pikelet config without restarting it" do
    expect(Flapjack::Logger).to receive(:new).and_return(logger)

    old_cfg = {'processor' => {'enabled' => true, 'foo' => 'bar'}}
    new_cfg = {'processor' => {'enabled' => true, 'foo' => 'baz'}}

    new_config = double('new_config')
    filename = double('filename')

    expect(config).to receive(:all).twice.and_return(old_cfg)
    expect(config).to receive(:filename).and_return(filename)

    expect(Flapjack::Configuration).to receive(:new).and_return(new_config)
    expect(new_config).to receive(:load).with(filename)
    expect(new_config).to receive(:all).and_return(new_cfg)

    processor = double('processor')
    expect(processor).not_to receive(:start)
    expect(processor).to receive(:type).exactly(3).times.and_return('processor')
    expect(processor).to receive(:reload).with(new_cfg['processor']).and_return(true)
    expect(processor).not_to receive(:stop)

    expect(config).to receive(:for_redis).and_return({})
    fc = Flapjack::Coordinator.new(config)
    fc.instance_variable_set('@boot_time', time)
    fc.instance_variable_set('@pikelets', [processor])
    fc.send(:reload)
    expect(fc.instance_variable_get('@pikelets')).to eq([processor])
  end

  it "reloads a pikelet config while restarting it" do
    expect(Flapjack::Logger).to receive(:new).and_return(logger)

    old_cfg = {'processor' => {'enabled' => true, 'foo' => 'bar'}}
    new_cfg = {'processor' => {'enabled' => true, 'baz' => 'qux'}}

    new_config = double('new_config')
    filename = double('filename')

    expect(config).to receive(:all).twice.and_return(old_cfg)
    expect(config).to receive(:filename).and_return(filename)

    expect(Flapjack::Configuration).to receive(:new).and_return(new_config)
    expect(new_config).to receive(:load).with(filename)
    expect(new_config).to receive(:all).and_return(new_cfg)

    processor = double('processor')
    expect(processor).to receive(:type).exactly(5).times.and_return('processor')
    expect(processor).to receive(:reload).with(new_cfg['processor']).and_return(false)
    expect(processor).to receive(:stop)
    expect(processor).to receive(:update_status)
    expect(processor).to receive(:status).exactly(3).times.and_return('stopped')

    new_exec = double('new_executive')
    expect(new_exec).to receive(:start)

    expect(config).to receive(:for_redis).and_return({})
    fc = Flapjack::Coordinator.new(config)

    expect(Flapjack::Pikelet).to receive(:create).
      with('processor', :config => new_cfg['processor'], :redis_config => {},
        :boot_time => time).
      and_return(new_exec)

    fc.instance_variable_set('@boot_time', time)
    fc.instance_variable_set('@pikelets', [processor])
    fc.send(:reload)
    expect(fc.instance_variable_get('@pikelets')).to eq([new_exec])
  end

end
