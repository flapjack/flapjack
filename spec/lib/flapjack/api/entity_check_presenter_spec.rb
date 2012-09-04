require 'spec_helper'
require 'flapjack/api/entity_check_presenter'

# require 'flapjack/data/entity'
# require 'flapjack/data/entity_check'

describe 'Flapjack::API::EntityCheck::Presenter' do

  let(:entity_check) { mock(Flapjack::Data::EntityCheck) }

  let(:time) { Time.now.to_i }

  let(:states) {
    [{:state => 'critical', :timestamp => time - (4 * 60 * 60)},
     {:state => 'ok',       :timestamp => time - (4 * 60 * 60) + (5 * 60)},
     {:state => 'critical', :timestamp => time - (3 * 60 * 60)},
     {:state => 'ok',       :timestamp => time - (3 * 60 * 60) + (10 * 60)},
     {:state => 'critical', :timestamp => time - (2 * 60 * 60)},
     {:state => 'ok',       :timestamp => time - (2 * 60 * 60) + (15 * 60)},
     {:state => 'critical', :timestamp => time - (1 * 60 * 60)},
     {:state => 'ok',       :timestamp => time - (1 * 60 * 60) + (20 * 60)}
    ]
  }

  # one overlap at start, one overlap at end, one wholly overlapping,
  # and one left un-overlapped
  let(:scheduled_maintenances) {
    [{:start_time => time - ((4 * 60 * 60) + (1 * 60)), # 1 minute before outage starts
      :end_time   => time - (4 * 60 * 60) + (2 * 60),   # 2 minutes after outage starts
      :duration => (3 * 60)},
     {:start_time => time - (3 * 60 * 60) + (8 * 60),   # 2 minutes before outage ends
      :end_time   => time - (3 * 60 * 60) + (11 * 60),  # 1 minute after outage ends
      :duration => (3 * 60)},
     {:start_time => time - ((2 * 60 * 60) + (1 * 60)), # i minute before outage starts
      :end_time   => time - (2 * 60 * 60) + (17 * 60),  # 2 minutes after outage ends
      :duration => (3 * 60)}
    ]
  }

  it "returns a list of outage hashes for an entity check" do
    entity_check.should_receive(:historical_states).
      with(time - (5 * 60 * 60), time - (2 * 60 * 60)).and_return(states)

    entity_check.should_receive(:historical_state_before).
      with(time - (4 * 60 * 60)).and_return(nil)

    ecp = Flapjack::API::EntityCheckPresenter.new(entity_check)
    outages = ecp.outages(time - (5 * 60 * 60), time - (2 * 60 * 60))
    outages.should_not be_nil
    outages.should be_an(Array)
    outages.should have(4).time_ranges

    # TODO check the data in those hashes
  end

  it "a list of unscheduled maintenances for an entity check"

  it "a list of scheduled maintenances for an entity check"

  # TODO test with overhanging maintenance period (i.e. starts before start
  # time of check)
  it "returns downtime and percentage for an entity check" do
    entity_check.should_receive(:historical_states).
      with(time - (12 * 60 * 60), time).and_return(states)

    entity_check.should_receive(:historical_state_before).
      with(time - (4 * 60 * 60)).and_return(nil)

    entity_check.should_receive(:historical_maintenances).
      with(time - (12 * 60 * 60), time, :scheduled => true).and_return(scheduled_maintenances)

    entity_check.should_receive(:historical_maintenances).
      with(nil, time - (12 * 60 * 60), :scheduled => true).and_return([])

    ecp = Flapjack::API::EntityCheckPresenter.new(entity_check)
    downtimes = ecp.downtime(time - (12 * 60 * 60), time)

    # 31 minutes, 3 + 8 + 20
    downtimes.should be_a(Hash)
    downtimes[:total_seconds].should == (31 * 60)
    downtimes[:percentage].should == (((31 * 60) * 100) / (12 * 60 * 60))
  end

end