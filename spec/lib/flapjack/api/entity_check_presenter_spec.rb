require 'spec_helper'
require 'flapjack/api/entity_check_presenter'

# require 'flapjack/data/entity'
# require 'flapjack/data/entity_check'

describe 'Flapjack::API::EntityCheck::Presenter' do

  let(:entity_check) { mock(Flapjack::Data::EntityCheck) }

  it "returns a hash of downtimes for an entity check" do
    t = Time.now.to_i

    five_hours_ago = t - (5 * 60 * 60)
    two_hours_ago  = t - (2 * 60 * 60)

    states = [
      {:state => 'critical', :timestamp => t - (4 * 60 * 60)},
      {:state => 'ok',       :timestamp => t - (4 * 60 * 60) + (5 * 60)},
      {:state => 'critical', :timestamp => t - (3 * 60 * 60) + (10 * 60)},
      {:state => 'ok',       :timestamp => t - (3 * 60 * 60) + (20 * 60)}
    ]

    entity_check.should_receive(:historical_states).
      with(five_hours_ago, two_hours_ago).and_return(states)

    entity_check.should_receive(:historical_state_before).
      with(t - (4 * 60 * 60)).and_return(nil)

    ecp = Flapjack::API::EntityCheckPresenter.new(entity_check)
    downtimes = ecp.outages(five_hours_ago, two_hours_ago)
    downtimes.should_not be_nil
    downtimes.should be_an(Array)
    downtimes.should have(2).time_ranges

    # TODO check the data in those hashes
  end

end