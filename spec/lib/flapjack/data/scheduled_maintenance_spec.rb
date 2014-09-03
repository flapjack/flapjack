require 'spec_helper'
require 'flapjack/data/scheduled_maintenance'

describe Flapjack::Data::ScheduledMaintenance, :redis => true do

  #   it "creates an unscheduled maintenance period from a human readable time" do
  #     Flapjack::Data::EntityCheck.create_maintenance(:redis => @redis, :entity => name, :check => check, :type => 'unscheduled', :started => '14/3/2027 3pm', :duration => '30 minutes', :reason => 'oops')
  #     t = Time.local(2027, 3, 14, 15, 0).to_i

  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
  #     expect(ec).to be_in_unscheduled_maintenance

  #     umps = ec.maintenances(nil, nil, :scheduled => false)
  #     expect(umps).not_to be_nil
  #     expect(umps).to be_an(Array)
  #     expect(umps.size).to eq(1)
  #     expect(umps[0]).to be_a(Hash)

  #     start_time = umps[0][:start_time]
  #     expect(start_time).not_to be_nil
  #     expect(start_time).to be_an(Integer)
  #     expect(start_time).to eq(t)

  #     duration = umps[0][:duration]
  #     expect(duration).not_to be_nil
  #     expect(duration).to be_a(Float)
  #     expect(duration).to eq(1800.0)

  #     summary = @redis.get("#{name}:#{check}:#{t}:unscheduled_maintenance:summary")
  #     expect(summary).not_to be_nil
  #     expect(summary).to eq('oops')
  #   end

  #   it "ends an unscheduled maintenance period", :time => true do
  #     t = Time.now.to_i
  #     later_t = t + (15 * 60)
  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)

  #     ec.create_unscheduled_maintenance(t, half_an_hour, :summary => 'oops')
  #     expect(ec).to be_in_unscheduled_maintenance

  #     Delorean.time_travel_to(Time.at(later_t))
  #     expect(ec).to be_in_unscheduled_maintenance
  #     ec.end_unscheduled_maintenance(later_t)
  #     expect(ec).not_to be_in_unscheduled_maintenance

  #     umps = ec.maintenances(nil, nil, :scheduled => false)
  #     expect(umps).not_to be_nil
  #     expect(umps).to be_an(Array)
  #     expect(umps.size).to eq(1)
  #     expect(umps[0]).to be_a(Hash)

  #     start_time = umps[0][:start_time]
  #     expect(start_time).not_to be_nil
  #     expect(start_time).to be_an(Integer)
  #     expect(start_time).to eq(t)

  #     duration = umps[0][:duration]
  #     expect(duration).not_to be_nil
  #     expect(duration).to be_a(Float)
  #     expect(duration).to eq(15 * 60)
  #   end

  #   it "creates a scheduled maintenance period for a future time" do
  #     t = Time.now.to_i
  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
  #     ec.create_scheduled_maintenance(t + (60 * 60),
  #                                     half_an_hour, :summary => "30 minutes")

  #     smps = ec.maintenances(nil, nil, :scheduled => true)
  #     expect(smps).not_to be_nil
  #     expect(smps).to be_an(Array)
  #     expect(smps.size).to eq(1)
  #     expect(smps[0]).to be_a(Hash)

  #     start_time = smps[0][:start_time]
  #     expect(start_time).not_to be_nil
  #     expect(start_time).to be_an(Integer)
  #     expect(start_time).to eq(t + (60 * 60))

  #     duration = smps[0][:duration]
  #     expect(duration).not_to be_nil
  #     expect(duration).to be_a(Float)
  #     expect(duration).to eq(half_an_hour)
  #   end

  #   # TODO this should probably enforce that it starts in the future
  #   it "creates a scheduled maintenance period covering the current time" do
  #     t = Time.now.to_i
  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
  #     ec.create_scheduled_maintenance(t - (60 * 60),
  #                                     2 * (60 * 60), :summary => "2 hours")

  #     smps = ec.maintenances(nil, nil, :scheduled => true)
  #     expect(smps).not_to be_nil
  #     expect(smps).to be_an(Array)
  #     expect(smps.size).to eq(1)
  #     expect(smps[0]).to be_a(Hash)

  #     start_time = smps[0][:start_time]
  #     expect(start_time).not_to be_nil
  #     expect(start_time).to be_an(Integer)
  #     expect(start_time).to eq(t - (60 * 60))

  #     duration = smps[0][:duration]
  #     expect(duration).not_to be_nil
  #     expect(duration).to be_a(Float)
  #     expect(duration).to eq(2 * (60 * 60))
  #   end

  #   it "creates an scheduled maintenance period from a human readable time" do
  #     Flapjack::Data::EntityCheck.create_maintenance(:redis => @redis, :entity => name, :check => check, :type => 'scheduled', :started => '14/3/2027 3pm', :duration => '30 minutes', :reason => 'oops')
  #     t = Time.local(2027, 3, 14, 15, 0).to_i
  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)

  #     smps = ec.maintenances(nil, nil, :scheduled => true)
  #     expect(smps).not_to be_nil
  #     expect(smps).to be_an(Array)
  #     expect(smps.size).to eq(1)
  #     expect(smps[0]).to be_a(Hash)

  #     start_time = smps[0][:start_time]
  #     expect(start_time).not_to be_nil
  #     expect(start_time).to be_an(Integer)
  #     expect(start_time).to eq(t)

  #     duration = smps[0][:duration]
  #     expect(duration).not_to be_nil
  #     expect(duration).to be_a(Float)
  #     expect(duration).to eq(1800.0)

  #     summary = @redis.get("#{name}:#{check}:#{t}:scheduled_maintenance:summary")
  #     expect(summary).not_to be_nil
  #     expect(summary).to eq('oops')
  #   end

  #   it "removes a scheduled maintenance period for a future time" do
  #     t = Time.now.to_i
  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
  #     ec.create_scheduled_maintenance(t + (60 * 60),
  #                                     2 * (60 * 60), :summary => "2 hours")

  #     ec.end_scheduled_maintenance(t + (60 * 60))

  #     smps = ec.maintenances(nil, nil, :scheduled => true)
  #     expect(smps).not_to be_nil
  #     expect(smps).to be_an(Array)
  #     expect(smps).to be_empty
  #   end

  #   # maint period starts an hour from now, goes for two hours -- at 30 minutes into
  #   # it we stop it, and its duration should be 30 minutes
  #   it "shortens a scheduled maintenance period covering a current time", :time => true do
  #     t = Time.now.to_i
  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
  #     ec.create_scheduled_maintenance(t + (60 * 60),
  #                                     2 * (60 * 60), :summary => "2 hours")

  #     Delorean.time_travel_to(Time.at(t + (90 * 60)))

  #     ec.end_scheduled_maintenance(t + (60 * 60))

  #     smps = ec.maintenances(nil, nil, :scheduled => true)
  #     expect(smps).not_to be_nil
  #     expect(smps).to be_an(Array)
  #     expect(smps).not_to be_empty
  #     expect(smps.size).to eq(1)
  #     expect(smps.first[:duration]).to eq(30 * 60)
  #   end

  #   it "does not alter or remove a scheduled maintenance period covering a past time", :time => true do
  #     t = Time.now.to_i
  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
  #     ec.create_scheduled_maintenance(t + (60 * 60),
  #                                     2 * (60 * 60), :summary => "2 hours")

  #     Delorean.time_travel_to(Time.at(t + (6 * (60 * 60))))

  #     ec.end_scheduled_maintenance(t + (60 * 60))

  #     smps = ec.maintenances(nil, nil, :scheduled => true)
  #     expect(smps).not_to be_nil
  #     expect(smps).to be_an(Array)
  #     expect(smps).not_to be_empty
  #     expect(smps.size).to eq(1)
  #     expect(smps.first[:duration]).to eq(2 * (60 * 60))
  #   end

  #   it "returns a list of scheduled maintenance periods" do
  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
  #     ec.create_scheduled_maintenance(five_hours_ago, half_an_hour,
  #                                     :summary => "first")
  #     ec.create_scheduled_maintenance(three_hours_ago, half_an_hour,
  #                                     :summary => "second")

  #     smp = ec.maintenances(nil, nil, :scheduled => true)
  #     expect(smp).not_to be_nil
  #     expect(smp).to be_an(Array)
  #     expect(smp.size).to eq(2)
  #     expect(smp[0]).to eq(:start_time => five_hours_ago,
  #                          :end_time   => five_hours_ago + half_an_hour,
  #                          :duration   => half_an_hour,
  #                          :summary    => "first")
  #     expect(smp[1]).to eq(:start_time => three_hours_ago,
  #                          :end_time   => three_hours_ago + half_an_hour,
  #                          :duration   => half_an_hour,
  #                          :summary    => "second")
  #   end

  #   it "returns a list of unscheduled maintenance periods" do
  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
  #     ec.create_unscheduled_maintenance(five_hours_ago,
  #                                       half_an_hour, :summary => "first")
  #     ec.create_unscheduled_maintenance(three_hours_ago,
  #                                       half_an_hour, :summary => "second")

  #     ump =  ec.maintenances(nil, nil, :scheduled => false)
  #     expect(ump).not_to be_nil
  #     expect(ump).to be_an(Array)
  #     expect(ump.size).to eq(2)
  #     expect(ump[0]).to eq(:start_time => five_hours_ago,
  #                          :end_time   => five_hours_ago + half_an_hour,
  #                          :duration   => half_an_hour,
  #                          :summary    => "first")
  #     expect(ump[1]).to eq(:start_time => three_hours_ago,
  #                          :end_time   => three_hours_ago + half_an_hour,
  #                          :duration   => half_an_hour,
  #                          :summary    => "second")
  #   end

  #   it "finds current scheduled maintenance periods for multiple entities" do
  #     ec = nil

  #     %w(alpha lima bravo).each do |entity|
  #       Flapjack::Data::Entity.add({ 'name' => entity }, :redis => @redis)

  #       ec = Flapjack::Data::EntityCheck.for_entity_name(entity, check, :redis => @redis)
  #       ec.create_scheduled_maintenance(five_hours_ago, seven_hours,
  #         :summary => "Test scheduled maintenance for #{entity}")
  #     end

  #     smp = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis,
  #       :type => 'scheduled', :finishing => 'more than 0 minutes from now').sort_by { |k| k[:entity] }

  #     expect(smp).to be_an(Array)
  #     expect(smp.size).to eq(3)
  #     %w(alpha bravo lima).each_with_index do |entity, index|
  #     expect(smp[index]).to eq(:entity     => entity,
  #                              :check      => "ping",
  #                              # The state here is nil due to no check having gone
  #                              # through for this item.  This is normally 'critical' or 'ok'
  #                              :state      => nil,
  #                              :start_time => five_hours_ago,
  #                              :end_time   => five_hours_ago + seven_hours,
  #                              :duration   => seven_hours,
  #                              :summary    => "Test scheduled maintenance for #{entity}")
  #     end
  #   end

  # it "finds current unscheduled maintenance periods for multiple entities" do
  #     ec = nil

  #     %w(alpha bravo lima).each do |entity|
  #       Flapjack::Data::Entity.add({ 'name' => entity }, :redis => @redis)

  #       ec = Flapjack::Data::EntityCheck.for_entity_name(entity, check, :redis => @redis)
  #       ec.create_unscheduled_maintenance(five_hours_ago, seven_hours, :summary => "Test unscheduled maintenance for #{entity}")
  #     end

  #     ump = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'unscheduled', :finishing => 'more than 0 minutes from now').sort_by { |k| k[:entity] }

  #     expect(ump).not_to be_nil
  #     expect(ump).to be_an(Array)
  #     expect(ump.size).to eq(3)
  #     %w(alpha bravo lima).each_with_index do |entity, index|
  #     expect(ump[index]).to eq(:entity     => entity,
  #                              :check      => "ping",
  #                              # The state here is nil due to no check having gone
  #                              # through for this item.  This is normally 'critical' or 'ok'
  #                              :state      => nil,
  #                              :start_time => five_hours_ago,
  #                              :end_time   => five_hours_ago + seven_hours,
  #                              :duration   => seven_hours,
  #                              :summary    => "Test unscheduled maintenance for #{entity}")
  #     end
  #   end

  #   it "finds all scheduled maintenance starting more than 3 hours ago" do
  #     ['more than three hours ago', 'before 3 hours ago'].each do |input|
  #       ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)

  #       # Maintenance in the past, now ended
  #       ec.create_scheduled_maintenance(five_hours_ago, half_an_hour, :summary => "30 minute maintenance")
  #       # Maintenance started in the past, still running
  #       ec.create_scheduled_maintenance(three_hours_ago + five_minutes, seven_hours, :summary => "Scheduled maintenance started 3 hours ago")
  #       ec.create_scheduled_maintenance(four_hours_ago, seven_hours, :summary => "Scheduled maintenance started 4 hours ago")

  #       smp = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled', :started => input).sort_by { |k| k[:entity] }

  #       expect(smp).to be_an(Array)
  #       expect(smp.size).to eq(2)

  #       expect(smp[0]).to eq(:entity     => name,
  #                            :check      => check,
  #                            # The state here is nil due to no check having gone
  #                            # through for this item.  This is normally 'critical' or 'ok'
  #                            :state      => nil,
  #                            :start_time => five_hours_ago,
  #                            :end_time   => five_hours_ago + half_an_hour,
  #                            :duration   => half_an_hour,
  #                            :summary    => "30 minute maintenance")
  #       expect(smp[1]).to eq(:entity     => name,
  #                            :check      => check,
  #                            # The state here is nil due to no check having gone
  #                            # through for this item.  This is normally 'critical' or 'ok'
  #                            :state      => nil,
  #                            :start_time => four_hours_ago,
  #                            :end_time   => four_hours_ago + seven_hours,
  #                            :duration   => seven_hours,
  #                            :summary    => "Scheduled maintenance started 4 hours ago")
  #     end
  #   end

  #   it "finds all scheduled maintenance starting within the next four hours" do
  #     ['less than four hours ago', 'after 4 hours ago'].each do |input|
  #       ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)

  #       # Maintenance in the past, now ended
  #       ec.create_scheduled_maintenance(five_hours_ago, half_an_hour, :summary => "30 minute maintenance")
  #       # Maintenance started in the past, still running
  #       ec.create_scheduled_maintenance(three_hours_ago, seven_hours, :summary => "Scheduled maintenance started 3 hours ago")
  #       ec.create_scheduled_maintenance(four_hours_ago, seven_hours, :summary => "Scheduled maintenance started 4 hours ago")

  #       smp = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled', :started => input).sort_by { |k| k[:entity] }

  #       expect(smp).to be_an(Array)
  #       expect(smp.size).to eq(1)

  #       expect(smp[0]).to eq(:entity     => name,
  #                            :check      => check,
  #                            # The state here is nil due to no check having gone
  #                            # through for this item.  This is normally 'critical' or 'ok'
  #                            :state      => nil,
  #                            :start_time => three_hours_ago,
  #                            :end_time   => three_hours_ago + seven_hours,
  #                            :duration   => seven_hours,
  #                            :summary    => "Scheduled maintenance started 3 hours ago")
  #     end
  #   end

  #   it "finds all scheduled maintenance ending within the next two hours" do
  #     ['less than two hours', 'before 2 hours'].each do |input|
  #       ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
  #       # Maintenance in the past, now ended
  #       ec.create_scheduled_maintenance(two_hours_ago + five_minutes, half_an_hour, :summary => "Scheduled maintenance started 3 hours ago")
  #       # Maintenance started in the past, still running
  #       ec.create_scheduled_maintenance(three_hours_ago, seven_hours, :summary => "Scheduled maintenance started 3 hours ago for 7 hours")
  #       ec.create_scheduled_maintenance(five_hours_ago, seven_hours + five_minutes, :summary => "Scheduled maintenance started 5 hours ago")
  #       # Current maintenance
  #       ec.create_scheduled_maintenance(t, half_an_hour, :summary => "Scheduled maintenance started now")
  #       # Future maintenance
  #       ec.create_scheduled_maintenance(t + five_minutes, half_an_hour, :summary => "Scheduled maintenance starting in 5 minutes")

  #       smp = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled', :finishing => input).sort_by { |k| k[:entity] }

  #       expect(smp).to be_an(Array)
  #       expect(smp.size).to eq(3)

  #       expect(smp[0]).to eq(:entity     => name,
  #                            :check      => check,
  #                            # The state here is nil due to no check having gone
  #                            # through for this item.  This is normally 'critical' or 'ok'
  #                            :state      => nil,
  #                            :start_time => two_hours_ago + five_minutes,
  #                            :end_time   => two_hours_ago + five_minutes + half_an_hour,
  #                            :duration   => half_an_hour,
  #                            :summary    => "Scheduled maintenance started 3 hours ago")
  #       expect(smp[1]).to eq(:entity     => name,
  #                            :check      => check,
  #                            # The state here is nil due to no check having gone
  #                            # through for this item.  This is normally 'critical' or 'ok'
  #                            :state      => nil,
  #                            :start_time => t,
  #                            :end_time   => t + half_an_hour,
  #                            :duration   => half_an_hour,
  #                            :summary    => "Scheduled maintenance started now")
  #       expect(smp[2]).to eq(:entity     => name,
  #                            :check      => check,
  #                            # The state here is nil due to no check having gone
  #                            # through for this item.  This is normally 'critical' or 'ok'
  #                            :state      => nil,
  #                            :start_time => t + five_minutes,
  #                            :end_time   => t + five_minutes + half_an_hour,
  #                            :duration   => half_an_hour,
  #                            :summary    => "Scheduled maintenance starting in 5 minutes")
  #     end
  #   end

  #   it "finds all scheduled maintenance ending between two times (1 hour ago - 2 hours ago)" do
  #       ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
  #       # Maintenance in the past, now ended
  #       ec.create_scheduled_maintenance(two_hours_ago + five_minutes, half_an_hour, :summary => "Scheduled maintenance started 1 hour, 55 minutes ago")
  #       # Maintenance started in the past, still running
  #       ec.create_scheduled_maintenance(three_hours_ago, seven_hours, :summary => "Scheduled maintenance started 3 hours ago for 7 hours")
  #       ec.create_scheduled_maintenance(five_hours_ago, three_hours + five_minutes, :summary => "Scheduled maintenance started 5 hours ago")
  #       # Future maintenance
  #       ec.create_scheduled_maintenance(t + five_minutes, half_an_hour, :summary => "Scheduled maintenance starting in 5 minutes")

  #       smp = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled', :finishing => 'between one and two hours ago').sort_by { |k| k[:entity] }

  #       expect(smp).to be_an(Array)
  #       expect(smp.size).to eq(2)

  #       expect(smp[0]).to eq(:entity     => name,
  #                            :check      => check,
  #                            # The state here is nil due to no check having gone
  #                            # through for this item.  This is normally 'critical' or 'ok'
  #                            :state      => nil,
  #                            :start_time => five_hours_ago,
  #                            :end_time   => five_hours_ago + three_hours + five_minutes,
  #                            :duration   => three_hours + five_minutes,
  #                            :summary    => "Scheduled maintenance started 5 hours ago")
  #       expect(smp[1]).to eq(:entity     => name,
  #                            :check      => check,
  #                            # The state here is nil due to no check having gone
  #                            # through for this item.  This is normally 'critical' or 'ok'
  #                            :state      => nil,
  #                            :start_time => two_hours_ago + five_minutes,
  #                            :end_time   => two_hours_ago + five_minutes + half_an_hour,
  #                            :duration   => half_an_hour,
  #                            :summary    => "Scheduled maintenance started 1 hour, 55 minutes ago")
  #   end

  #   it "finds all scheduled maintenance ending between two times (1 hour from now - 2 hours from now)" do
  #       ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
  #       # Maintenance in the past, now ended
  #       ec.create_scheduled_maintenance(two_hours_ago + five_minutes, half_an_hour, :summary => "Scheduled maintenance started 1 hour, 55 minutes ago")
  #       # Maintenance started in the past, still running
  #       ec.create_scheduled_maintenance(three_hours_ago, five_hours - five_minutes, :summary => "Scheduled maintenance started 3 hours ago for 4 hours, 25 minutes")
  #       ec.create_scheduled_maintenance(five_hours_ago, three_hours + five_minutes, :summary => "Scheduled maintenance started 5 hours ago")
  #       # Future maintenance
  #       ec.create_scheduled_maintenance(t + five_minutes, one_hour, :summary => "Scheduled maintenance starting in 5 minutes")

  #       smp = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled', :finishing => 'between one and two hours').sort_by { |k| k[:entity] }

  #       expect(smp).to be_an(Array)
  #       expect(smp.size).to eq(2)

  #       expect(smp[0]).to eq(:entity     => name,
  #                            :check      => check,
  #                            # The state here is nil due to no check having gone
  #                            # through for this item.  This is normally 'critical' or 'ok'
  #                            :state      => nil,
  #                            :start_time => three_hours_ago,
  #                            :end_time   => three_hours_ago + five_hours - five_minutes,
  #                            :duration   => five_hours - five_minutes,
  #                            :summary    => "Scheduled maintenance started 3 hours ago for 4 hours, 25 minutes")
  #       expect(smp[1]).to eq(:entity     => name,
  #                            :check      => check,
  #                            # The state here is nil due to no check having gone
  #                            # through for this item.  This is normally 'critical' or 'ok'
  #                            :state      => nil,
  #                            :start_time => t + five_minutes,
  #                            :end_time   => t + five_minutes + one_hour,
  #                            :duration   => one_hour,
  #                            :summary    => "Scheduled maintenance starting in 5 minutes")
  #   end

  #   it "finds all scheduled maintenance ending in more than two hours" do
  #     ['more than two hours', 'after 2 hours'].each do |input|
  #       ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
  #       # Maintenance in the past, now ended
  #       ec.create_scheduled_maintenance(two_hours_ago, half_an_hour, :summary => "Scheduled maintenance started 2 hours ago")
  #       # Maintenance started in the past, still running
  #       ec.create_scheduled_maintenance(three_hours_ago, seven_hours, :summary => "Scheduled maintenance started 3 hours ago for 7 hours")
  #       ec.create_scheduled_maintenance(five_hours_ago, seven_hours, :summary => "Scheduled maintenance started 5 hours ago")
  #       # Current maintenance
  #       ec.create_scheduled_maintenance(t, half_an_hour, :summary => "Scheduled maintenance started now")
  #       # Future maintenance
  #       ec.create_scheduled_maintenance(t + five_minutes, half_an_hour, :summary => "Scheduled maintenance starting in 5 minutes")

  #       smp = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled', :finishing => input).sort_by { |k| k[:entity] }

  #       expect(smp).to be_an(Array)
  #       expect(smp.size).to eq(1)

  #       expect(smp[0]).to eq(:entity     => name,
  #                            :check      => check,
  #                            # The state here is nil due to no check having gone
  #                            # through for this item.  This is normally 'critical' or 'ok'
  #                            :state      => nil,
  #                            :start_time => three_hours_ago,
  #                            :end_time   => three_hours_ago + seven_hours,
  #                            :duration   => seven_hours,
  #                            :summary    => "Scheduled maintenance started 3 hours ago for 7 hours")
  #     end
  #   end

  #   it "finds all scheduled maintenance with a duration of less than one hour" do
  #     ['less than', 'before'].each do |input|
  #       ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
  #       # Maintenance in the past, now ended
  #       ec.create_scheduled_maintenance(two_hours_ago, half_an_hour, :summary => "Scheduled maintenance started 3 hours ago")
  #       # Maintenance started in the past, still running
  #       ec.create_scheduled_maintenance(three_hours_ago, seven_hours, :summary => "Scheduled maintenance started 3 hours ago for 7 hours")
  #       ec.create_scheduled_maintenance(five_hours_ago, seven_hours, :summary => "Scheduled maintenance started 5 hours ago")
  #       # Current maintenance
  #       ec.create_scheduled_maintenance(t, half_an_hour, :summary => "Scheduled maintenance started now")
  #       # Future maintenance
  #       ec.create_scheduled_maintenance(t + five_minutes, half_an_hour, :summary => "Scheduled maintenance starting in 5 minutes")

  #       smp = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled', :duration => "#{input} one hour").sort_by { |k| k[:entity] }

  #       expect(smp).to be_an(Array)
  #       expect(smp.size).to eq(3)

  #       expect(smp[0]).to eq(:entity     => name,
  #                            :check      => check,
  #                            # The state here is nil due to no check having gone
  #                            # through for this item.  This is normally 'critical' or 'ok'
  #                            :state      => nil,
  #                            :start_time => two_hours_ago,
  #                            :end_time   => two_hours_ago + half_an_hour,
  #                            :duration   => half_an_hour,
  #                            :summary    => "Scheduled maintenance started 3 hours ago")
  #       expect(smp[1]).to eq(:entity     => name,
  #                            :check      => check,
  #                            # The state here is nil due to no check having gone
  #                            # through for this item.  This is normally 'critical' or 'ok'
  #                            :state      => nil,
  #                            :start_time => t,
  #                            :end_time   => t + half_an_hour,
  #                            :duration   => half_an_hour,
  #                            :summary    => "Scheduled maintenance started now")
  #       expect(smp[2]).to eq(:entity     => name,
  #                            :check      => check,
  #                            # The state here is nil due to no check having gone
  #                            # through for this item.  This is normally 'critical' or 'ok'
  #                            :state      => nil,
  #                            :start_time => t + five_minutes,
  #                            :end_time   => t + five_minutes + half_an_hour,
  #                            :duration   => half_an_hour,
  #                            :summary    => "Scheduled maintenance starting in 5 minutes")
  #     end
  #   end

  #   it "finds all scheduled maintenance with a duration of 30 minutes" do
  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
  #     # Maintenance in the past, now ended
  #     ec.create_scheduled_maintenance(two_hours_ago, half_an_hour, :summary => "Scheduled maintenance started 3 hours ago")
  #     # Maintenance started in the past, still running
  #     ec.create_scheduled_maintenance(three_hours_ago, seven_hours, :summary => "Scheduled maintenance started 3 hours ago for 7 hours")
  #     ec.create_scheduled_maintenance(five_hours_ago, seven_hours, :summary => "Scheduled maintenance started 5 hours ago")
  #     # Current maintenance
  #     ec.create_scheduled_maintenance(t, half_an_hour, :summary => "Scheduled maintenance started now")
  #     # Future maintenance
  #     ec.create_scheduled_maintenance(t + five_minutes, half_an_hour, :summary => "Scheduled maintenance starting in 5 minutes")

  #     smp = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled', :duration => '30 minutes').sort_by { |k| k[:entity] }

  #     expect(smp).to be_an(Array)
  #     expect(smp.size).to eq(3)

  #     expect(smp[0]).to eq(:entity     => name,
  #                          :check      => check,
  #                          # The state here is nil due to no check having gone
  #                          # through for this item.  This is normally 'critical' or 'ok'
  #                          :state      => nil,
  #                          :start_time => two_hours_ago,
  #                          :end_time   => two_hours_ago + half_an_hour,
  #                          :duration   => half_an_hour,
  #                          :summary    => "Scheduled maintenance started 3 hours ago")
  #     expect(smp[1]).to eq(:entity     => name,
  #                          :check      => check,
  #                          # The state here is nil due to no check having gone
  #                          # through for this item.  This is normally 'critical' or 'ok'
  #                          :state      => nil,
  #                          :start_time => t,
  #                          :end_time   => t + half_an_hour,
  #                          :duration   => half_an_hour,
  #                          :summary    => "Scheduled maintenance started now")
  #     expect(smp[2]).to eq(:entity     => name,
  #                          :check      => check,
  #                          # The state here is nil due to no check having gone
  #                          # through for this item.  This is normally 'critical' or 'ok'
  #                          :state      => nil,
  #                          :start_time => t + five_minutes,
  #                          :end_time   => t + five_minutes + half_an_hour,
  #                          :duration   => half_an_hour,
  #                          :summary    => "Scheduled maintenance starting in 5 minutes")
  #   end

  #   it "finds all scheduled maintenance with a duration of between 15 and 65 minutes" do
  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
  #     # Maintenance in the past, now ended
  #     ec.create_scheduled_maintenance(two_hours_ago, half_an_hour, :summary => "Scheduled maintenance started 3 hours ago")
  #     # Maintenance started in the past, still running
  #     ec.create_scheduled_maintenance(three_hours_ago, seven_hours, :summary => "Scheduled maintenance started 3 hours ago for 7 hours")
  #     ec.create_scheduled_maintenance(five_hours_ago, one_hour, :summary => "Scheduled maintenance started 5 hours ago")
  #     # Current maintenance
  #     ec.create_scheduled_maintenance(t, half_an_hour, :summary => "Scheduled maintenance started now")
  #     # Future maintenance
  #     ec.create_scheduled_maintenance(t + five_minutes, half_an_hour, :summary => "Scheduled maintenance starting in 5 minutes")

  #     smp = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled', :duration => 'between 15 and 65 minutes').sort_by { |k| k[:entity] }

  #     expect(smp).to be_an(Array)
  #     expect(smp.size).to eq(4)

  #     expect(smp[1]).to eq(:entity     => name,
  #                          :check      => check,
  #                          # The state here is nil due to no check having gone
  #                          # through for this item.  This is normally 'critical' or 'ok'
  #                          :state      => nil,
  #                          :start_time => two_hours_ago,
  #                          :end_time   => two_hours_ago + half_an_hour,
  #                          :duration   => half_an_hour,
  #                          :summary    => "Scheduled maintenance started 3 hours ago")
  #     expect(smp[0]).to eq(:entity     => name,
  #                          :check      => check,
  #                          # The state here is nil due to no check having gone
  #                          # through for this item.  This is normally 'critical' or 'ok'
  #                          :state      => nil,
  #                          :start_time => five_hours_ago,
  #                          :end_time   => five_hours_ago + one_hour,
  #                          :duration   => one_hour,
  #                          :summary    => "Scheduled maintenance started 5 hours ago")
  #     expect(smp[2]).to eq(:entity     => name,
  #                          :check      => check,
  #                          # The state here is nil due to no check having gone
  #                          # through for this item.  This is normally 'critical' or 'ok'
  #                          :state      => nil,
  #                          :start_time => t,
  #                          :end_time   => t + half_an_hour,
  #                          :duration   => half_an_hour,
  #                          :summary    => "Scheduled maintenance started now")
  #     expect(smp[3]).to eq(:entity     => name,
  #                          :check      => check,
  #                          # The state here is nil due to no check having gone
  #                          # through for this item.  This is normally 'critical' or 'ok'
  #                          :state      => nil,
  #                          :start_time => t + five_minutes,
  #                          :end_time   => t + five_minutes + half_an_hour,
  #                          :duration   => half_an_hour,
  #                          :summary    => "Scheduled maintenance starting in 5 minutes")
  #   end

  #   it "finds all scheduled maintenance with a duration of more than one hour" do
  #     ['more than, after'].each do |input|
  #       ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
  #       # Maintenance in the past, now ended
  #       ec.create_scheduled_maintenance(two_hours_ago, half_an_hour, :summary => "Scheduled maintenance started 3 hours ago")
  #       # Maintenance started in the past, still running
  #       ec.create_scheduled_maintenance(three_hours_ago, seven_hours, :summary => "Scheduled maintenance started 3 hours ago for 7 hours")
  #       ec.create_scheduled_maintenance(five_hours_ago, seven_hours, :summary => "Scheduled maintenance started 5 hours ago")
  #       # Current maintenance
  #       ec.create_scheduled_maintenance(t, half_an_hour, :summary => "Scheduled maintenance started now")
  #       # Future maintenance
  #       ec.create_scheduled_maintenance(t + five_minutes, half_an_hour, :summary => "Scheduled maintenance starting in 5 minutes")

  #       smp = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled', :duration => "#{input} one hour").sort_by { |k| k[:entity] }

  #       expect(smp).to be_an(Array)
  #       expect(smp.size).to eq(2)

  #       expect(smp[0]).to eq(:entity     => name,
  #                            :check      => check,
  #                            # The state here is nil due to no check having gone
  #                            # through for this item.  This is normally 'critical' or 'ok'
  #                            :state      => nil,
  #                            :start_time => five_hours_ago,
  #                            :end_time   => five_hours_ago + seven_hours,
  #                            :duration   => seven_hours,
  #                            :summary    => "Scheduled maintenance started 5 hours ago")
  #       expect(smp[1]).to eq(:entity     => name,
  #                            :check      => check,
  #                            # The state here is nil due to no check having gone
  #                            # through for this item.  This is normally 'critical' or 'ok'
  #                            :state      => nil,
  #                            :start_time => three_hours_ago,
  #                            :end_time   => three_hours_ago + seven_hours,
  #                            :duration   => seven_hours,
  #                            :summary    => "Scheduled maintenance started 3 hours ago for 7 hours")
  #     end
  #   end

  #   it "finds all scheduled maintenance with a particular entity name" do
  #     ['bravo', 'br.*'].each do |input|
  #       %w(alpha bravo lima).each do |entity|
  #         Flapjack::Data::Entity.add({ 'name' => entity }, :redis => @redis)

  #         ec = Flapjack::Data::EntityCheck.for_entity_name(entity, check, :redis => @redis)
  #         ec.create_scheduled_maintenance(five_hours_ago, seven_hours, :summary => "Test scheduled maintenance for #{entity}")
  #       end

  #       smp = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled', :entity => input ).sort_by { |k| k[:entity] }

  #       expect(smp).to be_an(Array)
  #       expect(smp.size).to eq(1)
  #       expect(smp[0]).to eq(:entity     => "bravo",
  #                            :check      => check,
  #                            # The state here is nil due to no check having gone
  #                            # through for this item.  This is normally 'critical' or 'ok'
  #                            :state      => nil,
  #                            :start_time => five_hours_ago,
  #                            :end_time   => five_hours_ago + seven_hours,
  #                            :duration   => seven_hours,
  #                            :summary    => "Test scheduled maintenance for bravo")
  #     end
  #   end

  #   it "finds all scheduled maintenance with a particular check name" do
  #     ['http', 'ht.*'].each do |input|
  #       %w(ping http ssh).each do |check|
  #         ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
  #         ec.create_scheduled_maintenance(five_hours_ago, seven_hours, :summary => "Test scheduled maintenance for #{check}")
  #       end

  #       smp = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled', :check => input ).sort_by { |k| k[:entity] }

  #       expect(smp).to be_an(Array)
  #       expect(smp.size).to eq(1)
  #       expect(smp[0]).to eq(:entity     => name,
  #                            :check      => "http",
  #                            # The state here is nil due to no check having gone
  #                            # through for this item.  This is normally 'critical' or 'ok'
  #                            :state      => nil,
  #                            :start_time => five_hours_ago,
  #                            :end_time   => five_hours_ago + seven_hours,
  #                            :duration   => seven_hours,
  #                            :summary    => "Test scheduled maintenance for http")
  #     end
  #   end

  #   it "finds all scheduled maintenance with a particular summary" do
  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)

  #     # Maintenance started in the past, still running
  #     ec.create_scheduled_maintenance(three_hours_ago, seven_hours, :summary => "Bring me a shrubbery!")
  #     # Current maintenance
  #     ec.create_scheduled_maintenance(t, half_an_hour, :summary => "Bring me a shrubbery!")
  #     # Future maintenance
  #     ec.create_scheduled_maintenance(t + five_minutes, half_an_hour, :summary => "Scheduled maintenance starting in 5 minutes")

  #     smp = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled', :reason => "Bring me a shrubbery!").sort_by { |k| k[:entity] }

  #     expect(smp).to be_an(Array)
  #     expect(smp.size).to eq(2)

  #     expect(smp[0]).to eq(:entity     => name,
  #                          :check      => check,
  #                          # The state here is nil due to no check having gone
  #                          # through for this item.  This is normally 'critical' or 'ok'
  #                          :state      => nil,
  #                          :start_time => three_hours_ago,
  #                          :end_time   => three_hours_ago + seven_hours,
  #                          :duration   => seven_hours,
  #                          :summary    => "Bring me a shrubbery!")
  #     expect(smp[1]).to eq(:entity     => name,
  #                          :check      => check,
  #                          # The state here is nil due to no check having gone
  #                          # through for this item.  This is normally 'critical' or 'ok'
  #                          :state      => nil,
  #                          :start_time => t,
  #                          :end_time   => t + half_an_hour,
  #                          :duration   => half_an_hour,
  #                          :summary    => "Bring me a shrubbery!")
  #   end

  #   it "finds all scheduled maintenance with a summary regex" do
  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)

  #     # Maintenance started in the past, still running
  #     ec.create_scheduled_maintenance(three_hours_ago, seven_hours, :summary => "Bring me a shrubbery!")
  #     # Current maintenance
  #     ec.create_scheduled_maintenance(t, half_an_hour, :summary => "Bring me a shrubbery!")
  #     # Future maintenance
  #     ec.create_scheduled_maintenance(t + five_minutes, half_an_hour, :summary => "Scheduled maintenance starting in 5 minutes")

  #     smp = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled', :reason => '.* shrubbery!').sort_by { |k| k[:entity] }

  #     expect(smp).to be_an(Array)
  #     expect(smp.size).to eq(2)

  #     expect(smp[0]).to eq(:entity     => name,
  #                          :check      => check,
  #                          # The state here is nil due to no check having gone
  #                          # through for this item.  This is normally 'critical' or 'ok'
  #                          :state      => nil,
  #                          :start_time => three_hours_ago,
  #                          :end_time   => three_hours_ago + seven_hours,
  #                          :duration   => seven_hours,
  #                          :summary    => "Bring me a shrubbery!")
  #     expect(smp[1]).to eq(:entity     => name,
  #                          :check      => check,
  #                          # The state here is nil due to no check having gone
  #                          # through for this item.  This is normally 'critical' or 'ok'
  #                          :state      => nil,
  #                          :start_time => t,
  #                          :end_time   => t + half_an_hour,
  #                          :duration   => half_an_hour,
  #                          :summary    => "Bring me a shrubbery!")
  #   end

  #   it "deletes scheduled maintenance from list" do
  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
  #     # Current maintenance
  #     ec.create_scheduled_maintenance(two_hours_ago, seven_hours, :summary => "Scheduled maintenance started 2 hours ago")
  #     ec.create_scheduled_maintenance(t + half_an_hour, half_an_hour, :summary => "Scheduled maintenance starting in half an hour")
  #     # Future maintenance
  #     ec.create_scheduled_maintenance(t + five_minutes, half_an_hour, :summary => "Scheduled maintenance starting in 5 minutes")

  #     smp = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled').sort_by { |k| k[:entity] }

  #     expect(smp).to be_an(Array)
  #     expect(smp.size).to eq(3)

  #     expect(smp[0]).to eq(:entity     => name,
  #                          :check      => check,
  #                          # The state here is nil due to no check having gone
  #                          # through for this item.  This is normally 'critical' or 'ok'
  #                          :state      => nil,
  #                          :start_time => two_hours_ago,
  #                          :end_time   => two_hours_ago + seven_hours,
  #                          :duration   => seven_hours,
  #                          :summary    => "Scheduled maintenance started 2 hours ago")
  #     expect(smp[1]).to eq(:entity     => name,
  #                          :check      => check,
  #                          # The state here is nil due to no check having gone
  #                          # through for this item.  This is normally 'critical' or 'ok'
  #                          :state      => nil,
  #                          :start_time => t + five_minutes,
  #                          :end_time   => t + five_minutes + half_an_hour,
  #                          :duration   => half_an_hour,
  #                          :summary    => "Scheduled maintenance starting in 5 minutes")
  #     expect(smp[2]).to eq(:entity     => name,
  #                          :check      => check,
  #                          # The state here is nil due to no check having gone
  #                          # through for this item.  This is normally 'critical' or 'ok'
  #                          :state      => nil,
  #                          :start_time => t + half_an_hour,
  #                          :end_time   => t + half_an_hour + half_an_hour,
  #                          :duration   => half_an_hour,
  #                          :summary    => "Scheduled maintenance starting in half an hour")

  #     delete = Flapjack::Data::EntityCheck.delete_maintenance(:redis => @redis, :type => 'scheduled', :duration => '30 minutes' )
  #     expect(delete).to eq({})

  #     remain = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled').sort_by { |k| k[:entity] }

  #     expect(remain).to be_an(Array)
  #     expect(remain.size).to eq(1)

  #     expect(remain[0]).to eq(:entity     => name,
  #                             :check      => check,
  #                             # The state here is nil due to no check having gone
  #                             # through for this item.  This is normally 'critical' or 'ok'
  #                             :state      => nil,
  #                             :start_time => two_hours_ago,
  #                             :end_time   => two_hours_ago + seven_hours,
  #                             :duration   => seven_hours,
  #                             :summary    => "Scheduled maintenance started 2 hours ago")
  #   end

  #   it "deletes unscheduled maintenance from list" do
  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
  #     ec.create_unscheduled_maintenance(t, half_an_hour, :summary => "Unscheduled maintenance starting now")

  #     ump = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'unscheduled').sort_by { |k| k[:entity] }
  #     expect(ump).to be_an(Array)
  #     expect(ump.size).to eq(1)

  #     expect(ump[0]).to eq(:entity     => name,
  #                             :check      => check,
  #                             # The state here is nil due to no check having gone
  #                             # through for this item.  This is normally 'critical' or 'ok'
  #                             :state      => nil,
  #                             :start_time => t,
  #                             :duration   => half_an_hour,
  #                             :end_time   => t + half_an_hour,
  #                             :summary    => "Unscheduled maintenance starting now")

  #     later_t = t + (15 * 60)
  #     Delorean.time_travel_to(Time.at(later_t))

  #     delete = Flapjack::Data::EntityCheck.delete_maintenance(:redis => @redis, :type => 'unscheduled', :duration => '30 minutes')
  #     expect(delete).to eq({})

  #     remain = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'unscheduled').sort_by { |k| k[:entity] }
  #     expect(remain).to be_an(Array)
  #     expect(remain.size).to eq(1)

  #     expect(remain[0]).to eq(:entity     => name,
  #                             :check      => check,
  #                             # The state here is nil due to no check having gone
  #                             # through for this item.  This is normally 'critical' or 'ok'
  #                             :state      => nil,
  #                             :start_time => t,
  #                             :duration   => half_an_hour,
  #                             :end_time   => t + half_an_hour,
  #                             :summary    => "Unscheduled maintenance starting now")
  #   end

  #   it "shows errors when deleting maintenance in the past" do
  #     Flapjack::Data::EntityCheck.create_maintenance(:redis => @redis, :entity => name, :check => check, :type => 'unscheduled', :started => '14/3/1927 3pm', :duration => '30 minutes', :reason => 'Unscheduled maintenance')
  #     t = Time.local(1927, 3, 14, 15, 0).to_i
  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)

  #     ump = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'unscheduled').sort_by { |k| k[:entity] }
  #     expect(ump).to be_an(Array)
  #     expect(ump.size).to eq(1)

  #     expect(ump[0]).to eq(:entity     => name,
  #                          :check      => check,
  #                          # The state here is nil due to no check having gone
  #                          # through for this item.  This is normally 'critical' or 'ok'
  #                          :state      => nil,
  #                          :start_time => t,
  #                          :duration   => half_an_hour,
  #                          :end_time   => t + half_an_hour,
  #                          :summary    => "Unscheduled maintenance")

  #     delete = Flapjack::Data::EntityCheck.delete_maintenance(:redis => @redis, :type => 'unscheduled', :duration => '30 minutes')
  #     expect(delete).to eq({"abc-123:ping:#{t}"=>"Maintenance can't be deleted as it finished in the past"})
  #   end
  # end


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
