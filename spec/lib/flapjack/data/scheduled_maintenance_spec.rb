require 'spec_helper'
require 'flapjack/data/scheduled_maintenance'

describe Flapjack::Data::ScheduledMaintenance, :redis => true do


  #   it "creates a scheduled maintenance period for a future time" do
  #     t = Time.now.to_i
  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
  #     ec.create_scheduled_maintenance(t + (60 * 60),
  #       half_an_hour, :summary => "30 minutes")

  #     smps = ec.maintenances(nil, nil, :scheduled => true)
  #     smps.should_not be_nil
  #     smps.should be_an(Array)
  #     smps.should have(1).scheduled_maintenance_period
  #     smps[0].should be_a(Hash)

  #     start_time = smps[0][:start_time]
  #     start_time.should_not be_nil
  #     start_time.should be_an(Integer)
  #     start_time.should == (t + (60 * 60))

  #     duration = smps[0][:duration]
  #     duration.should_not be_nil
  #     duration.should be_a(Float)
  #     duration.should == half_an_hour
  #   end

  #   # TODO this should probably enforce that it starts in the future
  #   it "creates a scheduled maintenance period covering the current time" do
  #     t = Time.now.to_i
  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
  #     ec.create_scheduled_maintenance(t - (60 * 60),
  #       2 * (60 * 60), :summary => "2 hours")

  #     smps = ec.maintenances(nil, nil, :scheduled => true)
  #     smps.should_not be_nil
  #     smps.should be_an(Array)
  #     smps.should have(1).scheduled_maintenance_period
  #     smps[0].should be_a(Hash)

  #     start_time = smps[0][:start_time]
  #     start_time.should_not be_nil
  #     start_time.should be_an(Integer)
  #     start_time.should == (t - (60 * 60))

  #     duration = smps[0][:duration]
  #     duration.should_not be_nil
  #     duration.should be_a(Float)
  #     duration.should == 2 * (60 * 60)
  #   end


end
