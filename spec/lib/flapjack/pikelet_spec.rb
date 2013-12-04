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
    Flapjack::Logger.should_receive(:new).and_return(logger)

    config.should_receive(:[]).with('logger').and_return(nil)

    fc = double('coordinator')

    processor = double('processor')
    processor.should_receive(:start)
    Flapjack::Processor.should_receive(:new).with(:config => config,
        :redis_config => redis_config, :boot_time => time, :logger => logger, :coordinator => fc).
      and_return(processor)

    fiber.should_receive(:resume)
    Fiber.should_receive(:new).and_yield.and_return(fiber)

    pik = Flapjack::Pikelet.create('processor', :config => config,
      :redis_config => redis_config, :boot_time => time, :coordinator => fc)
    pik.should be_a(Flapjack::Pikelet::Generic)
    pik.start
  end

  it "creates and starts a resque worker gateway" do
    Flapjack::Logger.should_receive(:new).and_return(logger)

    config.should_receive(:[]).with('logger').and_return(nil)
    config.should_receive(:[]).with('queue').and_return('email_notif')

    resque_redis = double('resque_redis')
    redis = double('redis')
    Flapjack::RedisPool.should_receive(:new).twice.and_return(resque_redis, redis)
    Resque.should_receive(:redis=).with(resque_redis)

    Flapjack::Gateways::Email.should_receive(:instance_variable_set).
      with('@config', config)
    Flapjack::Gateways::Email.should_receive(:instance_variable_set).
      with('@redis', redis)
    Flapjack::Gateways::Email.should_receive(:instance_variable_set).
      with('@logger', logger)

    worker = double('worker')
    worker.should_receive(:work).with(0.1)
    Flapjack::Gateways::Email.should_receive(:start)
    EM::Resque::Worker.should_receive(:new).with('email_notif').and_return(worker)

    fiber.should_receive(:resume)
    Fiber.should_receive(:new).and_yield.and_return(fiber)

    pik = Flapjack::Pikelet.create('email', :config => config,
      :redis_config => redis_config)
    pik.should be_a(Flapjack::Pikelet::Resque)
    pik.start
  end

  it "creates a thin server gateway" do
    Flapjack::Logger.should_receive(:new).and_return(logger)

    config.should_receive(:[]).with('logger').and_return(nil)
    config.should_receive(:[]).with('port').and_return(7654)
    config.should_receive(:[]).with('timeout').and_return(90)

    server = double('server')
    server.should_receive(:timeout=).with(90)
    server.should_receive(:start)
    Thin::Server.should_receive(:new).
      with(/^(?:\d{1,3}\.){3}\d{1,3}$/, 7654,
        Flapjack::Gateways::Web, :signals => false).
      and_return(server)

    Flapjack::Gateways::Web.should_receive(:instance_variable_set).
      with('@config', config)
    Flapjack::Gateways::Web.should_receive(:instance_variable_set).
      with('@redis_config', redis_config)
    Flapjack::Gateways::Web.should_receive(:instance_variable_set).
      with('@logger', logger)

    Flapjack::Gateways::Web.should_receive(:start)

    pik = Flapjack::Pikelet.create('web', :config => config,
      :redis_config => redis_config)
    pik.should be_a(Flapjack::Pikelet::Thin)
    pik.start
  end

end
