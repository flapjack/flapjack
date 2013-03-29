require 'spec_helper'
require 'flapjack/pikelet'

describe Flapjack::Pikelet do

  let(:config)       { mock('config') }
  let(:redis_config) { mock('redis_config') }

  let(:logger)     { mock(Flapjack::Logger) }

  let(:fiber) { mock(Fiber) }

  before do
    Flapjack::Pikelet::Resque.class_variable_set(:@@resque_pool, nil)
  end

  it "creates and starts an executive pikelet" do
    Flapjack::Logger.should_receive(:new).and_return(logger)

    config.should_receive(:[]).with('logger').and_return(nil)

    executive = mock('executive')
    executive.should_receive(:start)
    Flapjack::Executive.should_receive(:new).with(:config => config,
      :redis_config => redis_config, :logger => logger).and_return(executive)

    fiber.should_receive(:resume)
    Fiber.should_receive(:new).and_yield.and_return(fiber)

    pik = Flapjack::Pikelet.create('executive', :config => config,
      :redis_config => redis_config)
    pik.should be_a(Flapjack::Pikelet::Generic)
    pik.start
  end

  it "handles an exception raised by a jabber pikelet" do
    Flapjack::Logger.should_receive(:new).and_return(logger)
    logger.should_receive(:fatal)

    config.should_receive(:[]).with('logger').and_return(nil)

    jabber = mock('jabber')
    jabber.should_receive(:start).and_raise(RuntimeError)
    jabber.should_receive(:stop)
    Flapjack::Gateways::Jabber.should_receive(:new).with(:config => config,
      :redis_config => redis_config, :logger => logger).and_return(jabber)

    fiber.should_receive(:resume)
    Fiber.should_receive(:new).and_yield.and_return(fiber)

    pik = Flapjack::Pikelet.create('jabber', :config => config,
      :redis_config => redis_config)
    pik.should be_a(Flapjack::Pikelet::Generic)
    pik.start
  end

  it "creates and starts a resque worker gateway" do
    Flapjack::Logger.should_receive(:new).and_return(logger)

    config.should_receive(:[]).with('logger').and_return(nil)
    config.should_receive(:[]).with('queue').and_return('email_notif')

    redis = mock('redis')
    Flapjack::RedisPool.should_receive(:new).and_return(redis)
    Resque.should_receive(:redis=).with( redis )

    Flapjack::Gateways::Email.should_receive(:instance_variable_set).
      with('@config', config)
    Flapjack::Gateways::Email.should_receive(:instance_variable_set).
      with('@redis_config', redis_config)
    Flapjack::Gateways::Email.should_receive(:instance_variable_set).
      with('@logger', logger)

    worker = mock('worker')
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


  it "handles an exception raised by a resque worker gateway" do

    Flapjack::Logger.should_receive(:new).and_return(logger)
    logger.should_receive(:fatal)

    config.should_receive(:[]).with('logger').and_return(nil)
    config.should_receive(:[]).with('queue').and_return('email_notif')

    redis = mock('redis')
    Flapjack::RedisPool.should_receive(:new).and_return(redis)
    Resque.should_receive(:redis=).with( redis )

    Flapjack::Gateways::Email.should_receive(:instance_variable_set).
      with('@config', config)
    Flapjack::Gateways::Email.should_receive(:instance_variable_set).
      with('@redis_config', redis_config)
    Flapjack::Gateways::Email.should_receive(:instance_variable_set).
      with('@logger', logger)

    worker = mock('worker')
    worker.should_receive(:work).with(0.1).and_raise(RuntimeError)
    Flapjack::Gateways::Email.should_receive(:start)
    Flapjack::Gateways::Email.should_receive(:stop)
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

    server = mock('server')
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
