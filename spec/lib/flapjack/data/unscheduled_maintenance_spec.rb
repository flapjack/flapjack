require 'spec_helper'
require 'flapjack/data/unscheduled_maintenance'

describe Flapjack::Data::UnscheduledMaintenance, :redis => true do

  #   it "creates an unscheduled maintenance period" do
  #     t = Time.now.to_i
  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
  #     ec.create_unscheduled_maintenance(t, half_an_hour, :summary => 'oops')

  #     ec.should be_in_unscheduled_maintenance

  #     umps = ec.maintenances(nil, nil, :scheduled => false)
  #     umps.should_not be_nil
  #     umps.should be_an(Array)
  #     umps.should have(1).unscheduled_maintenance_period
  #     umps[0].should be_a(Hash)

  #     start_time = umps[0][:start_time]
  #     start_time.should_not be_nil
  #     start_time.should be_an(Integer)
  #     start_time.should == t

  #     duration = umps[0][:duration]
  #     duration.should_not be_nil
  #     duration.should be_a(Float)
  #     duration.should == half_an_hour

  #     summary = Flapjack.redis.get("#{name}:#{check}:#{t}:unscheduled_maintenance:summary")
  #     summary.should_not be_nil
  #     summary.should == 'oops'
  #   end

end