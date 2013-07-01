require 'spec_helper'
require 'flapjack/gateways/api/entity_presenter'

describe 'Flapjack::Gateways::API::EntityPresenter' do

  let(:entity) { mock(Flapjack::Data::Entity) }

  let(:check_a) { mock(Flapjack::Data::EntityCheck) }
  let(:check_b) { mock(Flapjack::Data::EntityCheck) }

  let(:checkpres_a) { mock(Flapjack::Gateways::API::EntityCheckPresenter) }
  let(:checkpres_b) { mock(Flapjack::Gateways::API::EntityCheckPresenter) }

  let(:time) { Time.now.to_i }

  let(:start_time) { time - (6 * 60 * 60) }
  let(:end_time)   { time - (2 * 60 * 60) }

  def expect_check_presenters
    entity.should_receive(:name).exactly(4).times.and_return('foo')
    entity.should_receive(:check_list).and_return(['ping', 'ssh'])
    Flapjack::Data::EntityCheck.should_receive(:for_entity).
      with(entity, 'ssh', anything).and_return(check_a)
    Flapjack::Data::EntityCheck.should_receive(:for_entity).
      with(entity, 'ping', anything).and_return(check_b)

    Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
      with(check_a).and_return(checkpres_a)
    Flapjack::Gateways::API::EntityCheckPresenter.should_receive(:new).
      with(check_b).and_return(checkpres_b)
  end

  it 'returns a list of status hashes for each check on an entity' do
    expect_check_presenters

    status_a = mock('status_a')
    status_b = mock('status_b')
    checkpres_a.should_receive(:status).and_return(status_a)
    checkpres_b.should_receive(:status).and_return(status_b)

    ep = Flapjack::Gateways::API::EntityPresenter.new(entity)
    status = ep.status
    status.should == [{:entity => entity.name, :check => 'ping', :status => status_b},
                      {:entity => entity.name, :check => 'ssh',  :status => status_a}]

  end

  it "returns a list of outage hashes for each check on an entity" do
    expect_check_presenters
    outages_a = mock('outages_a')
    outages_b = mock('outages_b')
    checkpres_a.should_receive(:outages).with(start_time, end_time).
      and_return(outages_a)
    checkpres_b.should_receive(:outages).with(start_time, end_time).
      and_return(outages_b)

    ep = Flapjack::Gateways::API::EntityPresenter.new(entity)
    outages = ep.outages(start_time, end_time)
    outages.should == [{:entity => entity.name, :check => 'ping', :outages => outages_b},
                       {:entity => entity.name, :check => 'ssh',  :outages => outages_a}]
  end

  it "returns a list of unscheduled maintenance periods for each check on an entity" do
    expect_check_presenters
    unsched_maint_a = mock('unsched_maint_a')
    unsched_maint_b = mock('unsched_maint_b')
    checkpres_a.should_receive(:unscheduled_maintenances).with(start_time, end_time).
      and_return(unsched_maint_a)
    checkpres_b.should_receive(:unscheduled_maintenances).with(start_time, end_time).
      and_return(unsched_maint_b)

    ep = Flapjack::Gateways::API::EntityPresenter.new(entity)
    unsched_maint = ep.unscheduled_maintenances(start_time, end_time)
    unsched_maint.should == [{:entity => entity.name, :check => 'ping', :unscheduled_maintenances => unsched_maint_b},
                             {:entity => entity.name, :check => 'ssh',  :unscheduled_maintenances => unsched_maint_a}]
  end

  it "returns a list of scheduled maintenance periods for each check on an entity" do
    expect_check_presenters
    sched_maint_a = mock('sched_maint_a')
    sched_maint_b = mock('sched_maint_b')
    checkpres_a.should_receive(:scheduled_maintenances).with(start_time, end_time).
      and_return(sched_maint_a)
    checkpres_b.should_receive(:scheduled_maintenances).with(start_time, end_time).
      and_return(sched_maint_b)

    ep = Flapjack::Gateways::API::EntityPresenter.new(entity)
    sched_maint = ep.scheduled_maintenances(start_time, end_time)
    sched_maint.should == [{:entity => entity.name, :check => 'ping', :scheduled_maintenances => sched_maint_b},
                           {:entity => entity.name, :check => 'ssh',  :scheduled_maintenances => sched_maint_a}]
  end

  it "returns a list of downtime for each check on an entity" do
    expect_check_presenters
    downtime_a = mock('downtime_a')
    downtime_b = mock('downtime_b')
    checkpres_a.should_receive(:downtime).with(start_time, end_time).
      and_return(downtime_a)
    checkpres_b.should_receive(:downtime).with(start_time, end_time).
      and_return(downtime_b)

    ep = Flapjack::Gateways::API::EntityPresenter.new(entity)
    downtime = ep.downtime(start_time, end_time)
    downtime.should == [{:entity => entity.name, :check => 'ping', :downtime => downtime_b},
                        {:entity => entity.name, :check => 'ssh',  :downtime => downtime_a}]
  end

end
