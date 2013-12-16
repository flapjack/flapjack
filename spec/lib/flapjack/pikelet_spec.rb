require 'spec_helper'
require 'flapjack/pikelet'

describe Flapjack::Pikelet do

  let(:config) { double('config') }
  let(:redis_config) { double('redis_config') }

  let(:logger) { double(Flapjack::Logger) }

  let(:fiber) { double(Fiber) }

  let(:time) { Time.now }

  before do
    Flapjack::Pikelet::Resque.class_variable_set(:@@resque_pool, nil)
  end

  it "creates and starts a processor pikelet" do
    expect(Flapjack::Logger).to receive(:new).and_return(logger)

    expect(config).to receive(:[]).with('logger').and_return(nil)

    fc = double('coordinator')

    processor = double('processor')
    expect(processor).to receive(:start)
    expect(Flapjack::Processor).to receive(:new).with(:config => config,
        :redis_config => redis_config, :boot_time => time, :logger => logger, :coordinator => fc).
      and_return(processor)

    expect(fiber).to receive(:resume)
    expect(Fiber).to receive(:new).and_yield.and_return(fiber)

    pik = Flapjack::Pikelet.create('processor', :config => config,
      :redis_config => redis_config, :boot_time => time, :coordinator => fc)
    expect(pik).to be_a(Flapjack::Pikelet::Generic)
    pik.start
  end

  it "creates and starts a resque worker gateway" do
    expect(Flapjack::Logger).to receive(:new).and_return(logger)

    expect(config).to receive(:[]).with('logger').and_return(nil)
    expect(config).to receive(:[]).with('queue').and_return('email_notif')

    resque_redis = double('resque_redis')
    redis = double('redis')
    expect(Flapjack::RedisPool).to receive(:new).twice.and_return(resque_redis, redis)
    expect(Resque).to receive(:redis=).with(resque_redis)

    expect(Flapjack::Gateways::Email).to receive(:instance_variable_set).
      with('@config', config)
    expect(Flapjack::Gateways::Email).to receive(:instance_variable_set).
      with('@redis', redis)
    expect(Flapjack::Gateways::Email).to receive(:instance_variable_set).
      with('@logger', logger)

    worker = double('worker')
    expect(worker).to receive(:work).with(0.1)
    expect(Flapjack::Gateways::Email).to receive(:start)
    expect(EM::Resque::Worker).to receive(:new).with('email_notif').and_return(worker)

    expect(fiber).to receive(:resume)
    expect(Fiber).to receive(:new).and_yield.and_return(fiber)

    pik = Flapjack::Pikelet.create('email', :config => config,
      :redis_config => redis_config)
    expect(pik).to be_a(Flapjack::Pikelet::Resque)
    pik.start
  end

  it "creates a thin server gateway" do
    expect(Flapjack::Logger).to receive(:new).and_return(logger)

    expect(config).to receive(:[]).with('logger').and_return(nil)
    expect(config).to receive(:[]).with('port').and_return(7654)
    expect(config).to receive(:[]).with('timeout').and_return(90)

    server = double('server')
    expect(server).to receive(:timeout=).with(90)
    expect(server).to receive(:start)
    expect(Thin::Server).to receive(:new).
      with(/^(?:\d{1,3}\.){3}\d{1,3}$/, 7654,
        Flapjack::Gateways::Web, :signals => false).
      and_return(server)

    expect(Flapjack::Gateways::Web).to receive(:instance_variable_set).
      with('@config', config)
    expect(Flapjack::Gateways::Web).to receive(:instance_variable_set).
      with('@redis_config', redis_config)
    expect(Flapjack::Gateways::Web).to receive(:instance_variable_set).
      with('@logger', logger)

    expect(Flapjack::Gateways::Web).to receive(:start)

    pik = Flapjack::Pikelet.create('web', :config => config,
      :redis_config => redis_config)
    expect(pik).to be_a(Flapjack::Pikelet::Thin)
    pik.start
  end

end
