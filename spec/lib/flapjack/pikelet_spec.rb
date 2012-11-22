require 'spec_helper'
require 'flapjack/pikelet'

describe Flapjack::Pikelet do

  # TODO

  # old coordinator specs


  # it "creates an executive pikelet" do
  #   exec = mock('executive')
  #   exec.should_receive(:bootstrap)
  #   Flapjack::Executive.should_receive(:new).and_return(exec)
  #   exec.should_receive(:is_a?).with(Flapjack::GenericPikelet).and_return(true)
  #   exec.should_receive(:main)

  #   fiber.should_receive(:resume)
  #   Fiber.should_receive(:new).and_yield.and_return(fiber)

  #   config.should_receive(:for_redis).and_return({})

  #   fc = Flapjack::Coordinator.new(config)
  #   fc.send(:build_pikelet, Flapjack::Executive, {'enabled' => 'yes'})
  #   pikelets = fc.instance_variable_get('@pikelets')
  #   pikelets.should_not be_nil
  #   pikelets.should be_an(Array)
  #   pikelets.should have(1).pikelet
  #   pikelets.first.should == {:fiber => fiber, :class => Flapjack::Executive, :instance => exec}
  # end

  # it "handles an exception raised by a fiber pikelet" do
  #   jabber = mock('jabber')
  #   jabber.should_receive(:bootstrap)
  #   Flapjack::Gateways::Jabber.should_receive(:new).and_return(jabber)
  #   jabber.should_receive(:is_a?).with(Flapjack::GenericPikelet).and_return(true)
  #   jabber.should_receive(:main).and_raise(RuntimeError)

  #   fiber.should_receive(:resume)
  #   Fiber.should_receive(:new).and_yield.and_return(fiber)

  #   config.should_receive(:for_redis).and_return({})

  #   fc = Flapjack::Coordinator.new(config)
  #   fc.should_receive(:stop)
  #   fc.send(:build_pikelet, Flapjack::Gateways::Jabber, {'enabled' => 'yes'})
  #   pikelets = fc.instance_variable_get('@pikelets')
  #   pikelets.should_not be_nil
  #   pikelets.should be_an(Array)
  #   pikelets.should have(1).pikelet
  #   pikelets.first.should == {:fiber => fiber, :class => Flapjack::Gateways::Jabber, :instance => jabber}
  # end

  # it "creates a resque worker pikelet" do
  #   redis = mock('redis')
  #   Flapjack::RedisPool.should_receive(:new).and_return(redis)
  #   Resque.should_receive(:redis=).with(redis)

  #   worker = mock('worker')
  #   EM::Resque::Worker.should_receive(:new).and_return(worker)
  #   worker.should_receive(:work)

  #   fiber.should_receive(:resume)
  #   Fiber.should_receive(:new).and_yield.and_return(fiber)

  #   config.should_receive(:for_redis).and_return({})

  #   fc = Flapjack::Coordinator.new(config)
  #   fc.send(:build_pikelet, Flapjack::Gateways::Email, {'enabled' => 'yes'})
  #   pikelets = fc.instance_variable_get('@pikelets')
  #   pikelets.should_not be_nil
  #   pikelets.should be_an(Array)
  #   pikelets.should have(1).pikelet
  #   pikelets.first.should == {:fiber => fiber, :class => Flapjack::Gateways::Email,
  #                             :instance => worker}
  # end

  # it "creates a thin server pikelet" do
  #   redis = mock('redis')

  #   server = mock('server')
  #   server.should_receive(:start)
  #   Thin::Server.should_receive(:new).
  #     with(/^(?:\d{1,3}\.){3}\d{1,3}$/, an_instance_of(Fixnum), Flapjack::Gateways::Web, :signals => false).
  #     and_return(server)

  #   Flapjack::RedisPool.should_receive(:new)

  #   config.should_receive(:for_redis).and_return({})

  #   fc = Flapjack::Coordinator.new(config)
  #   fc.send(:build_pikelet, Flapjack::Gateways::Web, {'enabled' => 'yes'})
  #   pikelets = fc.instance_variable_get('@pikelets')
  #   pikelets.should_not be_nil
  #   pikelets.should be_an(Array)
  #   pikelets.should have(1).pikelet
  #   pikelets.first.should == {:class => Flapjack::Gateways::Web, :instance => server}
  # end

  # # NB: exceptions are handled directly by the Thin pikelets


end