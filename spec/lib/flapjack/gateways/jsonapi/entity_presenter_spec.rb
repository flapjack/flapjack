require 'spec_helper'
require 'flapjack/gateways/jsonapi/entity_presenter'

describe 'Flapjack::Gateways::JSONAPI::EntityPresenter' do

  let(:entity) { double(Flapjack::Data::Entity) }

  let(:check_a) { double(Flapjack::Data::Check) }
  let(:check_b) { double(Flapjack::Data::Check) }

  let(:checkpres_a) { double(Flapjack::Gateways::JSONAPI::CheckPresenter) }
  let(:checkpres_b) { double(Flapjack::Gateways::JSONAPI::CheckPresenter) }

  let(:time) { Time.now.to_i }

  let(:start_time) { time - (6 * 60 * 60) }
  let(:end_time)   { time - (2 * 60 * 60) }

  def expect_check_presenters
    expect(check_a).to receive(:name).twice.and_return('ssh')
    expect(check_b).to receive(:name).twice.and_return('ping')
    all_checks = double('checks', :all => [check_a, check_b])

    expect(entity).to receive(:name).twice.and_return('foo')
    expect(entity).to receive(:checks).and_return(all_checks)

    expect(Flapjack::Gateways::JSONAPI::CheckPresenter).to receive(:new).
      with(check_a).and_return(checkpres_a)
    expect(Flapjack::Gateways::JSONAPI::CheckPresenter).to receive(:new).
      with(check_b).and_return(checkpres_b)
  end

  it 'returns a list of status hashes for each check on an entity' do
    expect_check_presenters

    status_a = double('status_a')
    status_b = double('status_b')
    expect(checkpres_a).to receive(:status).and_return(status_a)
    expect(checkpres_b).to receive(:status).and_return(status_b)

    ep = Flapjack::Gateways::JSONAPI::EntityPresenter.new(entity)
    status = ep.status
    expect(status).to eq([{:entity => 'foo', :check => 'ping', :status => status_b},
                      {:entity => 'foo', :check => 'ssh',  :status => status_a}])
  end

  it "returns a list of outage hashes for each check on an entity" do
    expect_check_presenters
    outages_a = double('outages_a')
    outages_b = double('outages_b')
    expect(checkpres_a).to receive(:outages).with(start_time, end_time).
      and_return(outages_a)
    expect(checkpres_b).to receive(:outages).with(start_time, end_time).
      and_return(outages_b)

    ep = Flapjack::Gateways::JSONAPI::EntityPresenter.new(entity)
    outages = ep.outages(start_time, end_time)
    expect(outages).to eq([{:entity => 'foo', :check => 'ping', :outages => outages_b},
                       {:entity => 'foo', :check => 'ssh',  :outages => outages_a}])
  end

  it "returns a list of unscheduled maintenance periods for each check on an entity" do
    expect_check_presenters
    unsched_maint_a = double('unsched_maint_a')
    unsched_maint_b = double('unsched_maint_b')
    expect(checkpres_a).to receive(:unscheduled_maintenances).with(start_time, end_time).
      and_return(unsched_maint_a)
    expect(checkpres_b).to receive(:unscheduled_maintenances).with(start_time, end_time).
      and_return(unsched_maint_b)

    ep = Flapjack::Gateways::JSONAPI::EntityPresenter.new(entity)
    unsched_maint = ep.unscheduled_maintenances(start_time, end_time)
    expect(unsched_maint).to eq([{:entity => 'foo', :check => 'ping', :unscheduled_maintenances => unsched_maint_b},
                             {:entity => 'foo', :check => 'ssh',  :unscheduled_maintenances => unsched_maint_a}])
  end

  it "returns a list of scheduled maintenance periods for each check on an entity" do
    expect_check_presenters
    sched_maint_a = double('sched_maint_a')
    sched_maint_b = double('sched_maint_b')
    expect(checkpres_a).to receive(:scheduled_maintenances).with(start_time, end_time).
      and_return(sched_maint_a)
    expect(checkpres_b).to receive(:scheduled_maintenances).with(start_time, end_time).
      and_return(sched_maint_b)

    ep = Flapjack::Gateways::JSONAPI::EntityPresenter.new(entity)
    sched_maint = ep.scheduled_maintenances(start_time, end_time)
    expect(sched_maint).to eq([{:entity => 'foo', :check => 'ping', :scheduled_maintenances => sched_maint_b},
                           {:entity => 'foo', :check => 'ssh',  :scheduled_maintenances => sched_maint_a}])
  end

  it "returns a list of downtime for each check on an entity" do
    expect_check_presenters
    downtime_a = double('downtime_a')
    downtime_b = double('downtime_b')
    expect(checkpres_a).to receive(:downtime).with(start_time, end_time).
      and_return(downtime_a)
    expect(checkpres_b).to receive(:downtime).with(start_time, end_time).
      and_return(downtime_b)

    ep = Flapjack::Gateways::JSONAPI::EntityPresenter.new(entity)
    downtime = ep.downtime(start_time, end_time)
    expect(downtime).to eq([{:entity => 'foo', :check => 'ping', :downtime => downtime_b},
                        {:entity => 'foo', :check => 'ssh',  :downtime => downtime_a}])
  end

end
