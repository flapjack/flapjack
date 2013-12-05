require 'spec_helper'
require 'flapjack/gateways/api/entity_presenter'

describe 'Flapjack::Gateways::API::EntityPresenter' do

  let(:entity) { double(Flapjack::Data::Entity) }

  let(:check_a) { double(Flapjack::Data::Check) }
  let(:check_b) { double(Flapjack::Data::Check) }

  let(:checkpres_a) { double(Flapjack::Gateways::API::CheckPresenter) }
  let(:checkpres_b) { double(Flapjack::Gateways::API::CheckPresenter) }

  let(:time) { Time.now.to_i }

  let(:start_time) { time - (6 * 60 * 60) }
  let(:end_time)   { time - (2 * 60 * 60) }

  def expect_check_presenters
    check_a.should_receive(:name).twice.and_return('ssh')
    check_b.should_receive(:name).twice.and_return('ping')
    all_entity_checks = double('entity_checks', :all => [check_a, check_b])

    entity.should_receive(:name).twice.and_return('foo')
    entity.should_receive(:checks).and_return(all_entity_checks)

    Flapjack::Gateways::API::CheckPresenter.should_receive(:new).
      with(check_a).and_return(checkpres_a)
    Flapjack::Gateways::API::CheckPresenter.should_receive(:new).
      with(check_b).and_return(checkpres_b)
  end

  it 'returns a list of status hashes for each check on an entity' do
    expect_check_presenters

    status_a = double('status_a')
    status_b = double('status_b')
    checkpres_a.should_receive(:status).and_return(status_a)
    checkpres_b.should_receive(:status).and_return(status_b)

    ep = Flapjack::Gateways::API::EntityPresenter.new(entity)
    status = ep.status
    status.should == [{:entity => 'foo', :check => 'ping', :status => status_b},
                      {:entity => 'foo', :check => 'ssh',  :status => status_a}]
  end

  it "returns a list of outage hashes for each check on an entity" do
    expect_check_presenters
    outages_a = double('outages_a')
    outages_b = double('outages_b')
    checkpres_a.should_receive(:outages).with(start_time, end_time).
      and_return(outages_a)
    checkpres_b.should_receive(:outages).with(start_time, end_time).
      and_return(outages_b)

    ep = Flapjack::Gateways::API::EntityPresenter.new(entity)
    outages = ep.outages(start_time, end_time)
    outages.should == [{:entity => 'foo', :check => 'ping', :outages => outages_b},
                       {:entity => 'foo', :check => 'ssh',  :outages => outages_a}]
  end

  it "returns a list of unscheduled maintenance periods for each check on an entity" do
    expect_check_presenters
    unsched_maint_a = double('unsched_maint_a')
    unsched_maint_b = double('unsched_maint_b')
    checkpres_a.should_receive(:unscheduled_maintenances).with(start_time, end_time).
      and_return(unsched_maint_a)
    checkpres_b.should_receive(:unscheduled_maintenances).with(start_time, end_time).
      and_return(unsched_maint_b)

    ep = Flapjack::Gateways::API::EntityPresenter.new(entity)
    unsched_maint = ep.unscheduled_maintenances(start_time, end_time)
    unsched_maint.should == [{:entity => 'foo', :check => 'ping', :unscheduled_maintenances => unsched_maint_b},
                             {:entity => 'foo', :check => 'ssh',  :unscheduled_maintenances => unsched_maint_a}]
  end

  it "returns a list of scheduled maintenance periods for each check on an entity" do
    expect_check_presenters
    sched_maint_a = double('sched_maint_a')
    sched_maint_b = double('sched_maint_b')
    checkpres_a.should_receive(:scheduled_maintenances).with(start_time, end_time).
      and_return(sched_maint_a)
    checkpres_b.should_receive(:scheduled_maintenances).with(start_time, end_time).
      and_return(sched_maint_b)

    ep = Flapjack::Gateways::API::EntityPresenter.new(entity)
    sched_maint = ep.scheduled_maintenances(start_time, end_time)
    sched_maint.should == [{:entity => 'foo', :check => 'ping', :scheduled_maintenances => sched_maint_b},
                           {:entity => 'foo', :check => 'ssh',  :scheduled_maintenances => sched_maint_a}]
  end

  it "returns a list of downtime for each check on an entity" do
    expect_check_presenters
    downtime_a = double('downtime_a')
    downtime_b = double('downtime_b')
    checkpres_a.should_receive(:downtime).with(start_time, end_time).
      and_return(downtime_a)
    checkpres_b.should_receive(:downtime).with(start_time, end_time).
      and_return(downtime_b)

    ep = Flapjack::Gateways::API::EntityPresenter.new(entity)
    downtime = ep.downtime(start_time, end_time)
    downtime.should == [{:entity => 'foo', :check => 'ping', :downtime => downtime_b},
                        {:entity => 'foo', :check => 'ssh',  :downtime => downtime_a}]
  end

end
