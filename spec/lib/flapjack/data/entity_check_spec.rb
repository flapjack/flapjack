require 'spec_helper'

require 'flapjack/data/entity'
require 'flapjack/data/entity_check'
require 'flapjack/data/tag_set'

describe Flapjack::Data::EntityCheck, :redis => true do

  let(:name)  { 'abc-123' }
  let(:check) { 'ping' }

  let(:half_an_hour) { 30 * 60 }
  let(:t) { Time.now.to_i }
  let(:five_minutes) { 60 * 5 }
  let(:five_hours_ago) { t.to_i - (60 * 60 * 5) }
  let(:four_hours_ago) { t.to_i - (60 * 60 * 4) }
  let(:three_hours_ago) { t.to_i - (60 * 60 * 3) }
  let(:two_hours_ago) { t.to_i - (60 * 60 * 2) }
  let(:one_hour) { 60 * 60 }
  let(:two_hours) { 60 * 60 * 2 }
  let(:three_hours) { 60 * 60 * 3 }
  let(:five_hours) { 60 * 60 * 5 }
  let(:seven_hours) { 60 * 60 * 7 }

  before(:each) do
    Flapjack::Data::Contact.add({ 'id'         => '362',
                                  'first_name' => 'John',
                                  'last_name'  => 'Johnson',
                                  'email'      => 'johnj@example.com' },
                                :redis       => @redis)

    Flapjack::Data::Entity.add({ 'id'   => '5000',
                                 'name' => name,
                                 'contacts' => ['362'] },
                               :redis => @redis)
  end

  it "is created for an event id" do
    ec = Flapjack::Data::EntityCheck.for_event_id("#{name}:ping", :redis => @redis)
    expect(ec).not_to be_nil
    expect(ec.entity).not_to be_nil
    expect(ec.entity.name).not_to be_nil
    expect(ec.entity.name).to eq(name)
    expect(ec.check).not_to be_nil
    expect(ec.check).to eq('ping')
  end

  it "is created for an entity name" do
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, 'ping', :redis => @redis)
    expect(ec).not_to be_nil
    expect(ec.entity).not_to be_nil
    expect(ec.entity.name).not_to be_nil
    expect(ec.entity.name).to eq(name)
    expect(ec.check).not_to be_nil
    expect(ec.check).to eq('ping')
  end

  it "is created for an entity id" do
    ec = Flapjack::Data::EntityCheck.for_entity_id(5000, 'ping', :redis => @redis)
    expect(ec).not_to be_nil
    expect(ec.entity).not_to be_nil
    expect(ec.entity.name).not_to be_nil
    expect(ec.entity.name).to eq(name)
    expect(ec.check).not_to be_nil
    expect(ec.check).to eq('ping')
  end

  it "is created for an entity object" do
    e = Flapjack::Data::Entity.find_by_name(name, :redis => @redis)
    ec = Flapjack::Data::EntityCheck.for_entity(e, 'ping', :redis => @redis)
    expect(ec).not_to be_nil
    expect(ec.entity).not_to be_nil
    expect(ec.entity.name).not_to be_nil
    expect(ec.entity.name).to eq(name)
    expect(ec.check).not_to be_nil
    expect(ec.check).to eq('ping')
  end

  it "is not created for a missing entity" do
    expect {
      Flapjack::Data::EntityCheck.for_entity(nil, 'ping', :redis => @redis)
    }.to raise_error
  end

  it "raises an error if not created with a redis connection handle" do
    expect {
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, 'ping')
    }.to raise_error
  end

  context "maintenance" do

    it "returns that it is in unscheduled maintenance" do
      @redis.set("#{name}:#{check}:unscheduled_maintenance", Time.now.to_i.to_s)

      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      expect(ec).to be_in_unscheduled_maintenance
    end

    it "returns that it is not in unscheduled maintenance" do
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      expect(ec).not_to be_in_unscheduled_maintenance
    end

    it "returns that it is in scheduled maintenance" do
      @redis.set("#{name}:#{check}:scheduled_maintenance", Time.now.to_i.to_s)

      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      expect(ec).to be_in_scheduled_maintenance
    end

    it "returns that it is not in scheduled maintenance" do
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      expect(ec).not_to be_in_scheduled_maintenance
    end

    it "returns its current maintenance period" do
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      expect(ec.current_maintenance(:scheduled => true)).to be_nil

      t = Time.now.to_i

      ec.create_unscheduled_maintenance(t, half_an_hour, :summary => 'oops')
      expect(ec.current_maintenance).to eq(:start_time => t,
                                           :duration => half_an_hour,
                                           :summary => 'oops')
    end

    it "creates an unscheduled maintenance period" do
      t = Time.now.to_i
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      ec.create_unscheduled_maintenance(t, half_an_hour, :summary => 'oops')

      expect(ec).to be_in_unscheduled_maintenance

      umps = ec.maintenances(nil, nil, :scheduled => false)
      expect(umps).not_to be_nil
      expect(umps).to be_an(Array)
      expect(umps.size).to eq(1)
      expect(umps[0]).to be_a(Hash)

      start_time = umps[0][:start_time]
      expect(start_time).not_to be_nil
      expect(start_time).to be_an(Integer)
      expect(start_time).to eq(t)

      duration = umps[0][:duration]
      expect(duration).not_to be_nil
      expect(duration).to be_a(Float)
      expect(duration).to eq(half_an_hour)

      summary = @redis.get("#{name}:#{check}:#{t}:unscheduled_maintenance:summary")
      expect(summary).not_to be_nil
      expect(summary).to eq('oops')
    end

    it "creates an unscheduled maintenance period and ends the current one early", :time => true do
      t = Time.now.to_i
      later_t = t + (15 * 60)
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      ec.create_unscheduled_maintenance(t, half_an_hour, :summary => 'oops')
      Delorean.time_travel_to(Time.at(later_t))
      ec.create_unscheduled_maintenance(later_t, half_an_hour, :summary => 'spoo')

      expect(ec).to be_in_unscheduled_maintenance

      umps = ec.maintenances(nil, nil, :scheduled => false)
      expect(umps).not_to be_nil
      expect(umps).to be_an(Array)
      expect(umps.size).to eq(2)
      expect(umps[0]).to be_a(Hash)

      start_time = umps[0][:start_time]
      expect(start_time).not_to be_nil
      expect(start_time).to be_an(Integer)
      expect(start_time).to eq(t)

      duration = umps[0][:duration]
      expect(duration).not_to be_nil
      expect(duration).to be_a(Float)
      expect(duration).to eq(15 * 60)

      start_time_curr = umps[1][:start_time]
      expect(start_time_curr).not_to be_nil
      expect(start_time_curr).to be_an(Integer)
      expect(start_time_curr).to eq(later_t)

      duration_curr = umps[1][:duration]
      expect(duration_curr).not_to be_nil
      expect(duration_curr).to be_a(Float)
      expect(duration_curr).to eq(half_an_hour)
    end

    it "creates an unscheduled maintenance period from a human readable time" do
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      ec.create_unscheduled_maintenance('14/3/2027 3pm', '30 minutes', :summary => 'oops')
      t = Time.local(2027, 3, 14, 15, 0).to_i

      expect(ec).to be_in_unscheduled_maintenance

      umps = ec.maintenances(nil, nil, :scheduled => false)
      expect(umps).not_to be_nil
      expect(umps).to be_an(Array)
      expect(umps.size).to eq(1)
      expect(umps[0]).to be_a(Hash)

      start_time = umps[0][:start_time]
      expect(start_time).not_to be_nil
      expect(start_time).to be_an(Integer)
      expect(start_time).to eq(t)

      duration = umps[0][:duration]
      expect(duration).not_to be_nil
      expect(duration).to be_a(Float)
      expect(duration).to eq(1800.0)

      summary = @redis.get("#{name}:#{check}:#{t}:unscheduled_maintenance:summary")
      expect(summary).not_to be_nil
      expect(summary).to eq('oops')
    end

    it "ends an unscheduled maintenance period", :time => true do
      t = Time.now.to_i
      later_t = t + (15 * 60)
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)

      ec.create_unscheduled_maintenance(t, half_an_hour, :summary => 'oops')
      expect(ec).to be_in_unscheduled_maintenance

      Delorean.time_travel_to(Time.at(later_t))
      expect(ec).to be_in_unscheduled_maintenance
      ec.end_unscheduled_maintenance(later_t)
      expect(ec).not_to be_in_unscheduled_maintenance

      umps = ec.maintenances(nil, nil, :scheduled => false)
      expect(umps).not_to be_nil
      expect(umps).to be_an(Array)
      expect(umps.size).to eq(1)
      expect(umps[0]).to be_a(Hash)

      start_time = umps[0][:start_time]
      expect(start_time).not_to be_nil
      expect(start_time).to be_an(Integer)
      expect(start_time).to eq(t)

      duration = umps[0][:duration]
      expect(duration).not_to be_nil
      expect(duration).to be_a(Float)
      expect(duration).to eq(15 * 60)
    end

    it "creates a scheduled maintenance period for a future time" do
      t = Time.now.to_i
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      ec.create_scheduled_maintenance(t + (60 * 60),
                                      half_an_hour, :summary => "30 minutes")

      smps = ec.maintenances(nil, nil, :scheduled => true)
      expect(smps).not_to be_nil
      expect(smps).to be_an(Array)
      expect(smps.size).to eq(1)
      expect(smps[0]).to be_a(Hash)

      start_time = smps[0][:start_time]
      expect(start_time).not_to be_nil
      expect(start_time).to be_an(Integer)
      expect(start_time).to eq(t + (60 * 60))

      duration = smps[0][:duration]
      expect(duration).not_to be_nil
      expect(duration).to be_a(Float)
      expect(duration).to eq(half_an_hour)
    end

    # TODO this should probably enforce that it starts in the future
    it "creates a scheduled maintenance period covering the current time" do
      t = Time.now.to_i
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      ec.create_scheduled_maintenance(t - (60 * 60),
                                      2 * (60 * 60), :summary => "2 hours")

      smps = ec.maintenances(nil, nil, :scheduled => true)
      expect(smps).not_to be_nil
      expect(smps).to be_an(Array)
      expect(smps.size).to eq(1)
      expect(smps[0]).to be_a(Hash)

      start_time = smps[0][:start_time]
      expect(start_time).not_to be_nil
      expect(start_time).to be_an(Integer)
      expect(start_time).to eq(t - (60 * 60))

      duration = smps[0][:duration]
      expect(duration).not_to be_nil
      expect(duration).to be_a(Float)
      expect(duration).to eq(2 * (60 * 60))
    end

    it "creates an scheduled maintenance period from a human readable time" do
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      ec.create_scheduled_maintenance('14/3/2027 3pm', '30 minutes', :summary => 'oops')
      t = Time.local(2027, 3, 14, 15, 0).to_i

      smps = ec.maintenances(nil, nil, :scheduled => true)
      expect(smps).not_to be_nil
      expect(smps).to be_an(Array)
      expect(smps.size).to eq(1)
      expect(smps[0]).to be_a(Hash)

      start_time = smps[0][:start_time]
      expect(start_time).not_to be_nil
      expect(start_time).to be_an(Integer)
      expect(start_time).to eq(t)

      duration = smps[0][:duration]
      expect(duration).not_to be_nil
      expect(duration).to be_a(Float)
      expect(duration).to eq(1800.0)

      summary = @redis.get("#{name}:#{check}:#{t}:scheduled_maintenance:summary")
      expect(summary).not_to be_nil
      expect(summary).to eq('oops')
    end

    it "removes a scheduled maintenance period for a future time" do
      t = Time.now.to_i
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      ec.create_scheduled_maintenance(t + (60 * 60),
                                      2 * (60 * 60), :summary => "2 hours")

      ec.end_scheduled_maintenance(t + (60 * 60))

      smps = ec.maintenances(nil, nil, :scheduled => true)
      expect(smps).not_to be_nil
      expect(smps).to be_an(Array)
      expect(smps).to be_empty
    end

    # maint period starts an hour from now, goes for two hours -- at 30 minutes into
    # it we stop it, and its duration should be 30 minutes
    it "shortens a scheduled maintenance period covering a current time", :time => true do
      t = Time.now.to_i
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      ec.create_scheduled_maintenance(t + (60 * 60),
                                      2 * (60 * 60), :summary => "2 hours")

      Delorean.time_travel_to(Time.at(t + (90 * 60)))

      ec.end_scheduled_maintenance(t + (60 * 60))

      smps = ec.maintenances(nil, nil, :scheduled => true)
      expect(smps).not_to be_nil
      expect(smps).to be_an(Array)
      expect(smps).not_to be_empty
      expect(smps.size).to eq(1)
      expect(smps.first[:duration]).to eq(30 * 60)
    end

    it "does not alter or remove a scheduled maintenance period covering a past time", :time => true do
      t = Time.now.to_i
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      ec.create_scheduled_maintenance(t + (60 * 60),
                                      2 * (60 * 60), :summary => "2 hours")

      Delorean.time_travel_to(Time.at(t + (6 * (60 * 60))))

      ec.end_scheduled_maintenance(t + (60 * 60))

      smps = ec.maintenances(nil, nil, :scheduled => true)
      expect(smps).not_to be_nil
      expect(smps).to be_an(Array)
      expect(smps).not_to be_empty
      expect(smps.size).to eq(1)
      expect(smps.first[:duration]).to eq(2 * (60 * 60))
    end

    it "returns a list of scheduled maintenance periods" do
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      ec.create_scheduled_maintenance(five_hours_ago, half_an_hour,
                                      :summary => "first")
      ec.create_scheduled_maintenance(three_hours_ago, half_an_hour,
                                      :summary => "second")

      smp = ec.maintenances(nil, nil, :scheduled => true)
      expect(smp).not_to be_nil
      expect(smp).to be_an(Array)
      expect(smp.size).to eq(2)
      expect(smp[0]).to eq(:start_time => five_hours_ago,
                           :end_time   => five_hours_ago + half_an_hour,
                           :duration   => half_an_hour,
                           :summary    => "first")
      expect(smp[1]).to eq(:start_time => three_hours_ago,
                           :end_time   => three_hours_ago + half_an_hour,
                           :duration   => half_an_hour,
                           :summary    => "second")
    end

    it "returns a list of unscheduled maintenance periods" do
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      ec.create_unscheduled_maintenance(five_hours_ago,
                                        half_an_hour, :summary => "first")
      ec.create_unscheduled_maintenance(three_hours_ago,
                                        half_an_hour, :summary => "second")

      ump =  ec.maintenances(nil, nil, :scheduled => false)
      expect(ump).not_to be_nil
      expect(ump).to be_an(Array)
      expect(ump.size).to eq(2)
      expect(ump[0]).to eq(:start_time => five_hours_ago,
                           :end_time   => five_hours_ago + half_an_hour,
                           :duration   => half_an_hour,
                           :summary    => "first")
      expect(ump[1]).to eq(:start_time => three_hours_ago,
                           :end_time   => three_hours_ago + half_an_hour,
                           :duration   => half_an_hour,
                           :summary    => "second")
    end

    it "finds current scheduled maintenance period for entities over multiple hosts" do
      ec = nil

      %w(alpha lima bravo).each do |entity|
        Flapjack::Data::Entity.add({ 'name' => entity }, :redis => @redis)

        ec = Flapjack::Data::EntityCheck.for_entity_name(entity, check, :redis => @redis)
        ec.create_scheduled_maintenance(five_hours_ago, seven_hours, :summary => "Test scheduled maintenance for #{entity}")
      end

      smp = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled', :finishing => 'more than 0 minutes from now').sort_by { |k| k[:entity] }

      expect(smp).to be_an(Array)
      expect(smp.size).to eq(3)
      %w(alpha bravo lima).each_with_index do |entity, index|
      expect(smp[index]).to eq(:entity     => entity,
                               :check      => "ping",
                               # The state here is nil due to no check having gone
                               # through for this item.  This is normally 'critical' or 'ok'
                               :state      => nil,
                               :start_time => five_hours_ago,
                               :end_time   => five_hours_ago + seven_hours,
                               :duration   => seven_hours,
                               :summary    => "Test scheduled maintenance for #{entity}")
      end
    end

    it "finds current unscheduled maintenance period for entities over multiple hosts" do
      ec = nil

      %w(alpha bravo lima).each do |entity|
        Flapjack::Data::Entity.add({ 'name' => entity }, :redis => @redis)

        ec = Flapjack::Data::EntityCheck.for_entity_name(entity, check, :redis => @redis)
        ec.create_unscheduled_maintenance(five_hours_ago, seven_hours, :summary => "Test unscheduled maintenance for #{entity}")
      end

      ump = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'unscheduled', :finishing => 'more than 0 minutes from now').sort_by { |k| k[:entity] }

      expect(ump).not_to be_nil
      expect(ump).to be_an(Array)
      expect(ump.size).to eq(3)
      %w(alpha bravo lima).each_with_index do |entity, index|
      expect(ump[index]).to eq(:entity     => entity,
                               :check      => "ping",
                               # The state here is nil due to no check having gone
                               # through for this item.  This is normally 'critical' or 'ok'
                               :state      => nil,
                               :start_time => five_hours_ago,
                               :end_time   => five_hours_ago + seven_hours,
                               :duration   => seven_hours,
                               :summary    => "Test unscheduled maintenance for #{entity}")
      end
    end

    it "finds all scheduled maintenance before a given start time (more than 3 hours ago)" do
      ['more than three hours ago', 'before 3 hours ago'].each do |input|
        ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)

        # Maintenance in the past, now ended
        ec.create_scheduled_maintenance(five_hours_ago, half_an_hour, :summary => "30 minute maintenance")
        # Maintenance started in the past, still running
        ec.create_scheduled_maintenance(three_hours_ago, seven_hours, :summary => "Scheduled maintenance started 3 hours ago")
        ec.create_scheduled_maintenance(four_hours_ago, seven_hours, :summary => "Scheduled maintenance started 4 hours ago")

        smp = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled', :started => input).sort_by { |k| k[:entity] }

        expect(smp).to be_an(Array)
        expect(smp.size).to eq(2)

        expect(smp[0]).to eq(:entity     => name,
                             :check      => check,
                             # The state here is nil due to no check having gone
                             # through for this item.  This is normally 'critical' or 'ok'
                             :state      => nil,
                             :start_time => five_hours_ago,
                             :end_time   => five_hours_ago + half_an_hour,
                             :duration   => half_an_hour,
                             :summary    => "30 minute maintenance")
        expect(smp[1]).to eq(:entity     => name,
                             :check      => check,
                             # The state here is nil due to no check having gone
                             # through for this item.  This is normally 'critical' or 'ok'
                             :state      => nil,
                             :start_time => four_hours_ago,
                             :end_time   => four_hours_ago + seven_hours,
                             :duration   => seven_hours,
                             :summary    => "Scheduled maintenance started 4 hours ago")
      end
    end

    it "finds all scheduled maintenance after a given start time (less than 4 hours ago)" do
      ['less than four hours ago', 'after 4 hours ago'].each do |input|
        ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)

        # Maintenance in the past, now ended
        ec.create_scheduled_maintenance(five_hours_ago, half_an_hour, :summary => "30 minute maintenance")
        # Maintenance started in the past, still running
        ec.create_scheduled_maintenance(three_hours_ago, seven_hours, :summary => "Scheduled maintenance started 3 hours ago")
        ec.create_scheduled_maintenance(four_hours_ago, seven_hours, :summary => "Scheduled maintenance started 4 hours ago")

        smp = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled', :started => input).sort_by { |k| k[:entity] }

        expect(smp).to be_an(Array)
        expect(smp.size).to eq(1)

        expect(smp[0]).to eq(:entity     => name,
                             :check      => check,
                             # The state here is nil due to no check having gone
                             # through for this item.  This is normally 'critical' or 'ok'
                             :state      => nil,
                             :start_time => three_hours_ago,
                             :end_time   => three_hours_ago + seven_hours,
                             :duration   => seven_hours,
                             :summary    => "Scheduled maintenance started 3 hours ago")
      end
    end

    it "finds all scheduled maintenance before a given end time (less than now + 2 hours)" do
      ['less than two hours', 'before 2 hours'].each do |input|
        ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
        # Maintenance in the past, now ended
        ec.create_scheduled_maintenance(two_hours_ago + five_minutes, half_an_hour, :summary => "Scheduled maintenance started 3 hours ago")
        # Maintenance started in the past, still running
        ec.create_scheduled_maintenance(three_hours_ago, seven_hours, :summary => "Scheduled maintenance started 3 hours ago for 7 hours")
        ec.create_scheduled_maintenance(five_hours_ago, seven_hours + five_minutes, :summary => "Scheduled maintenance started 5 hours ago")
        # Current maintenance
        ec.create_scheduled_maintenance(t, half_an_hour, :summary => "Scheduled maintenance started now")
        # Future maintenance
        ec.create_scheduled_maintenance(t + five_minutes, half_an_hour, :summary => "Scheduled maintenance starting in 5 minutes")

        smp = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled', :finishing => input).sort_by { |k| k[:entity] }

        expect(smp).to be_an(Array)
        expect(smp.size).to eq(3)

        expect(smp[0]).to eq(:entity     => name,
                             :check      => check,
                             # The state here is nil due to no check having gone
                             # through for this item.  This is normally 'critical' or 'ok'
                             :state      => nil,
                             :start_time => two_hours_ago + five_minutes,
                             :end_time   => two_hours_ago + five_minutes + half_an_hour,
                             :duration   => half_an_hour,
                             :summary    => "Scheduled maintenance started 3 hours ago")
        expect(smp[1]).to eq(:entity     => name,
                             :check      => check,
                             # The state here is nil due to no check having gone
                             # through for this item.  This is normally 'critical' or 'ok'
                             :state      => nil,
                             :start_time => t,
                             :end_time   => t + half_an_hour,
                             :duration   => half_an_hour,
                             :summary    => "Scheduled maintenance started now")
        expect(smp[2]).to eq(:entity     => name,
                             :check      => check,
                             # The state here is nil due to no check having gone
                             # through for this item.  This is normally 'critical' or 'ok'
                             :state      => nil,
                             :start_time => t + five_minutes,
                             :end_time   => t + five_minutes + half_an_hour,
                             :duration   => half_an_hour,
                             :summary    => "Scheduled maintenance starting in 5 minutes")
      end
    end

    it "finds all scheduled maintenance between two given end times (1 hour ago - 2 hours ago)" do
        ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
        # Maintenance in the past, now ended
        ec.create_scheduled_maintenance(two_hours_ago + five_minutes, half_an_hour, :summary => "Scheduled maintenance started 1 hour, 55 minutes ago")
        # Maintenance started in the past, still running
        ec.create_scheduled_maintenance(three_hours_ago, seven_hours, :summary => "Scheduled maintenance started 3 hours ago for 7 hours")
        ec.create_scheduled_maintenance(five_hours_ago, three_hours + five_minutes, :summary => "Scheduled maintenance started 5 hours ago")
        # Future maintenance
        ec.create_scheduled_maintenance(t + five_minutes, half_an_hour, :summary => "Scheduled maintenance starting in 5 minutes")

        smp = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled', :finishing => 'between one and two hours ago').sort_by { |k| k[:entity] }

        expect(smp).to be_an(Array)
        expect(smp.size).to eq(2)

        expect(smp[0]).to eq(:entity     => name,
                             :check      => check,
                             # The state here is nil due to no check having gone
                             # through for this item.  This is normally 'critical' or 'ok'
                             :state      => nil,
                             :start_time => five_hours_ago,
                             :end_time   => five_hours_ago + three_hours + five_minutes,
                             :duration   => three_hours + five_minutes,
                             :summary    => "Scheduled maintenance started 5 hours ago")
        expect(smp[1]).to eq(:entity     => name,
                             :check      => check,
                             # The state here is nil due to no check having gone
                             # through for this item.  This is normally 'critical' or 'ok'
                             :state      => nil,
                             :start_time => two_hours_ago + five_minutes,
                             :end_time   => two_hours_ago + five_minutes + half_an_hour,
                             :duration   => half_an_hour,
                             :summary    => "Scheduled maintenance started 1 hour, 55 minutes ago")
    end

    it "finds all scheduled maintenance between two given end times (1 hour from now - 2 hours from now)" do
        ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
        # Maintenance in the past, now ended
        ec.create_scheduled_maintenance(two_hours_ago + five_minutes, half_an_hour, :summary => "Scheduled maintenance started 1 hour, 55 minutes ago")
        # Maintenance started in the past, still running
        ec.create_scheduled_maintenance(three_hours_ago, five_hours - five_minutes, :summary => "Scheduled maintenance started 3 hours ago for 4 hours, 25 minutes")
        ec.create_scheduled_maintenance(five_hours_ago, three_hours + five_minutes, :summary => "Scheduled maintenance started 5 hours ago")
        # Future maintenance
        ec.create_scheduled_maintenance(t + five_minutes, one_hour, :summary => "Scheduled maintenance starting in 5 minutes")

        smp = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled', :finishing => 'between one and two hours').sort_by { |k| k[:entity] }

        expect(smp).to be_an(Array)
        expect(smp.size).to eq(2)

        expect(smp[0]).to eq(:entity     => name,
                             :check      => check,
                             # The state here is nil due to no check having gone
                             # through for this item.  This is normally 'critical' or 'ok'
                             :state      => nil,
                             :start_time => three_hours_ago,
                             :end_time   => three_hours_ago + five_hours - five_minutes,
                             :duration   => five_hours - five_minutes,
                             :summary    => "Scheduled maintenance started 3 hours ago for 4 hours, 25 minutes")
        expect(smp[1]).to eq(:entity     => name,
                             :check      => check,
                             # The state here is nil due to no check having gone
                             # through for this item.  This is normally 'critical' or 'ok'
                             :state      => nil,
                             :start_time => t + five_minutes,
                             :end_time   => t + five_minutes + one_hour,
                             :duration   => one_hour,
                             :summary    => "Scheduled maintenance starting in 5 minutes")
    end

    it "finds all scheduled maintenance after a given end time (more than 2 hours)" do
      ['more than two hours', 'after 2 hours'].each do |input|
        ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
        # Maintenance in the past, now ended
        ec.create_scheduled_maintenance(two_hours_ago, half_an_hour, :summary => "Scheduled maintenance started 2 hours ago")
        # Maintenance started in the past, still running
        ec.create_scheduled_maintenance(three_hours_ago, seven_hours, :summary => "Scheduled maintenance started 3 hours ago for 7 hours")
        ec.create_scheduled_maintenance(five_hours_ago, seven_hours, :summary => "Scheduled maintenance started 5 hours ago")
        # Current maintenance
        ec.create_scheduled_maintenance(t, half_an_hour, :summary => "Scheduled maintenance started now")
        # Future maintenance
        ec.create_scheduled_maintenance(t + five_minutes, half_an_hour, :summary => "Scheduled maintenance starting in 5 minutes")

        smp = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled', :finishing => input).sort_by { |k| k[:entity] }

        expect(smp).to be_an(Array)
        expect(smp.size).to eq(1)

        expect(smp[0]).to eq(:entity     => name,
                             :check      => check,
                             # The state here is nil due to no check having gone
                             # through for this item.  This is normally 'critical' or 'ok'
                             :state      => nil,
                             :start_time => three_hours_ago,
                             :end_time   => three_hours_ago + seven_hours,
                             :duration   => seven_hours,
                             :summary    => "Scheduled maintenance started 3 hours ago for 7 hours")
      end
    end

    it "finds all scheduled maintenance of less than one hour" do
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      # Maintenance in the past, now ended
      ec.create_scheduled_maintenance(two_hours_ago, half_an_hour, :summary => "Scheduled maintenance started 3 hours ago")
      # Maintenance started in the past, still running
      ec.create_scheduled_maintenance(three_hours_ago, seven_hours, :summary => "Scheduled maintenance started 3 hours ago for 7 hours")
      ec.create_scheduled_maintenance(five_hours_ago, seven_hours, :summary => "Scheduled maintenance started 5 hours ago")
      # Current maintenance
      ec.create_scheduled_maintenance(t, half_an_hour, :summary => "Scheduled maintenance started now")
      # Future maintenance
      ec.create_scheduled_maintenance(t + five_minutes, half_an_hour, :summary => "Scheduled maintenance starting in 5 minutes")

      smp = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled', :duration => 'less than one hour').sort_by { |k| k[:entity] }

      expect(smp).to be_an(Array)
      expect(smp.size).to eq(3)

      expect(smp[0]).to eq(:entity     => name,
                           :check      => check,
                           # The state here is nil due to no check having gone
                           # through for this item.  This is normally 'critical' or 'ok'
                           :state      => nil,
                           :start_time => two_hours_ago,
                           :end_time   => two_hours_ago + half_an_hour,
                           :duration   => half_an_hour,
                           :summary    => "Scheduled maintenance started 3 hours ago")
      expect(smp[1]).to eq(:entity     => name,
                           :check      => check,
                           # The state here is nil due to no check having gone
                           # through for this item.  This is normally 'critical' or 'ok'
                           :state      => nil,
                           :start_time => t,
                           :end_time   => t + half_an_hour,
                           :duration   => half_an_hour,
                           :summary    => "Scheduled maintenance started now")
      expect(smp[2]).to eq(:entity     => name,
                           :check      => check,
                           # The state here is nil due to no check having gone
                           # through for this item.  This is normally 'critical' or 'ok'
                           :state      => nil,
                           :start_time => t + five_minutes,
                           :end_time   => t + five_minutes + half_an_hour,
                           :duration   => half_an_hour,
                           :summary    => "Scheduled maintenance starting in 5 minutes")
    end

    it "finds all scheduled maintenance of 30 minutes" do
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      # Maintenance in the past, now ended
      ec.create_scheduled_maintenance(two_hours_ago, half_an_hour, :summary => "Scheduled maintenance started 3 hours ago")
      # Maintenance started in the past, still running
      ec.create_scheduled_maintenance(three_hours_ago, seven_hours, :summary => "Scheduled maintenance started 3 hours ago for 7 hours")
      ec.create_scheduled_maintenance(five_hours_ago, seven_hours, :summary => "Scheduled maintenance started 5 hours ago")
      # Current maintenance
      ec.create_scheduled_maintenance(t, half_an_hour, :summary => "Scheduled maintenance started now")
      # Future maintenance
      ec.create_scheduled_maintenance(t + five_minutes, half_an_hour, :summary => "Scheduled maintenance starting in 5 minutes")

      smp = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled', :duration => '30 minutes').sort_by { |k| k[:entity] }

      expect(smp).to be_an(Array)
      expect(smp.size).to eq(3)

      expect(smp[0]).to eq(:entity     => name,
                           :check      => check,
                           # The state here is nil due to no check having gone
                           # through for this item.  This is normally 'critical' or 'ok'
                           :state      => nil,
                           :start_time => two_hours_ago,
                           :end_time   => two_hours_ago + half_an_hour,
                           :duration   => half_an_hour,
                           :summary    => "Scheduled maintenance started 3 hours ago")
      expect(smp[1]).to eq(:entity     => name,
                           :check      => check,
                           # The state here is nil due to no check having gone
                           # through for this item.  This is normally 'critical' or 'ok'
                           :state      => nil,
                           :start_time => t,
                           :end_time   => t + half_an_hour,
                           :duration   => half_an_hour,
                           :summary    => "Scheduled maintenance started now")
      expect(smp[2]).to eq(:entity     => name,
                           :check      => check,
                           # The state here is nil due to no check having gone
                           # through for this item.  This is normally 'critical' or 'ok'
                           :state      => nil,
                           :start_time => t + five_minutes,
                           :end_time   => t + five_minutes + half_an_hour,
                           :duration   => half_an_hour,
                           :summary    => "Scheduled maintenance starting in 5 minutes")
    end

    it "finds all scheduled maintenance of between 15 and 65 minutes" do
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      # Maintenance in the past, now ended
      ec.create_scheduled_maintenance(two_hours_ago, half_an_hour, :summary => "Scheduled maintenance started 3 hours ago")
      # Maintenance started in the past, still running
      ec.create_scheduled_maintenance(three_hours_ago, seven_hours, :summary => "Scheduled maintenance started 3 hours ago for 7 hours")
      ec.create_scheduled_maintenance(five_hours_ago, one_hour, :summary => "Scheduled maintenance started 5 hours ago")
      # Current maintenance
      ec.create_scheduled_maintenance(t, half_an_hour, :summary => "Scheduled maintenance started now")
      # Future maintenance
      ec.create_scheduled_maintenance(t + five_minutes, half_an_hour, :summary => "Scheduled maintenance starting in 5 minutes")

      smp = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled', :duration => 'between 15 and 65 minutes').sort_by { |k| k[:entity] }

      expect(smp).to be_an(Array)
      expect(smp.size).to eq(4)

      expect(smp[1]).to eq(:entity     => name,
                           :check      => check,
                           # The state here is nil due to no check having gone
                           # through for this item.  This is normally 'critical' or 'ok'
                           :state      => nil,
                           :start_time => two_hours_ago,
                           :end_time   => two_hours_ago + half_an_hour,
                           :duration   => half_an_hour,
                           :summary    => "Scheduled maintenance started 3 hours ago")
      expect(smp[0]).to eq(:entity     => name,
                           :check      => check,
                           # The state here is nil due to no check having gone
                           # through for this item.  This is normally 'critical' or 'ok'
                           :state      => nil,
                           :start_time => five_hours_ago,
                           :end_time   => five_hours_ago + one_hour,
                           :duration   => one_hour,
                           :summary    => "Scheduled maintenance started 5 hours ago")
      expect(smp[2]).to eq(:entity     => name,
                           :check      => check,
                           # The state here is nil due to no check having gone
                           # through for this item.  This is normally 'critical' or 'ok'
                           :state      => nil,
                           :start_time => t,
                           :end_time   => t + half_an_hour,
                           :duration   => half_an_hour,
                           :summary    => "Scheduled maintenance started now")
      expect(smp[3]).to eq(:entity     => name,
                           :check      => check,
                           # The state here is nil due to no check having gone
                           # through for this item.  This is normally 'critical' or 'ok'
                           :state      => nil,
                           :start_time => t + five_minutes,
                           :end_time   => t + five_minutes + half_an_hour,
                           :duration   => half_an_hour,
                           :summary    => "Scheduled maintenance starting in 5 minutes")
    end

    it "finds all scheduled maintenance of more than one hour" do
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      # Maintenance in the past, now ended
      ec.create_scheduled_maintenance(two_hours_ago, half_an_hour, :summary => "Scheduled maintenance started 3 hours ago")
      # Maintenance started in the past, still running
      ec.create_scheduled_maintenance(three_hours_ago, seven_hours, :summary => "Scheduled maintenance started 3 hours ago for 7 hours")
      ec.create_scheduled_maintenance(five_hours_ago, seven_hours, :summary => "Scheduled maintenance started 5 hours ago")
      # Current maintenance
      ec.create_scheduled_maintenance(t, half_an_hour, :summary => "Scheduled maintenance started now")
      # Future maintenance
      ec.create_scheduled_maintenance(t + five_minutes, half_an_hour, :summary => "Scheduled maintenance starting in 5 minutes")

      smp = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled', :duration => 'more than one hour').sort_by { |k| k[:entity] }

      expect(smp).to be_an(Array)
      expect(smp.size).to eq(2)

      expect(smp[0]).to eq(:entity     => name,
                           :check      => check,
                           # The state here is nil due to no check having gone
                           # through for this item.  This is normally 'critical' or 'ok'
                           :state      => nil,
                           :start_time => five_hours_ago,
                           :end_time   => five_hours_ago + seven_hours,
                           :duration   => seven_hours,
                           :summary    => "Scheduled maintenance started 5 hours ago")
      expect(smp[1]).to eq(:entity     => name,
                           :check      => check,
                           # The state here is nil due to no check having gone
                           # through for this item.  This is normally 'critical' or 'ok'
                           :state      => nil,
                           :start_time => three_hours_ago,
                           :end_time   => three_hours_ago + seven_hours,
                           :duration   => seven_hours,
                           :summary    => "Scheduled maintenance started 3 hours ago for 7 hours")
    end

    it "finds all scheduled maintenance with a particular entity name" do
      ['bravo', 'br.*'].each do |input|
        %w(alpha bravo lima).each do |entity|
          Flapjack::Data::Entity.add({ 'name' => entity }, :redis => @redis)

          ec = Flapjack::Data::EntityCheck.for_entity_name(entity, check, :redis => @redis)
          ec.create_scheduled_maintenance(five_hours_ago, seven_hours, :summary => "Test scheduled maintenance for #{entity}")
        end

        smp = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled', :entity => input ).sort_by { |k| k[:entity] }

        expect(smp).to be_an(Array)
        expect(smp.size).to eq(1)
        expect(smp[0]).to eq(:entity     => "bravo",
                             :check      => check,
                             # The state here is nil due to no check having gone
                             # through for this item.  This is normally 'critical' or 'ok'
                             :state      => nil,
                             :start_time => five_hours_ago,
                             :end_time   => five_hours_ago + seven_hours,
                             :duration   => seven_hours,
                             :summary    => "Test scheduled maintenance for bravo")
      end
    end

    it "finds all scheduled maintenance with a particular check name" do
      ['http', 'ht.*'].each do |input|
        %w(ping http ssh).each do |check|
          ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
          ec.create_scheduled_maintenance(five_hours_ago, seven_hours, :summary => "Test scheduled maintenance for #{check}")
        end

        smp = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled', :check => input ).sort_by { |k| k[:entity] }

        expect(smp).to be_an(Array)
        expect(smp.size).to eq(1)
        expect(smp[0]).to eq(:entity     => name,
                             :check      => "http",
                             # The state here is nil due to no check having gone
                             # through for this item.  This is normally 'critical' or 'ok'
                             :state      => nil,
                             :start_time => five_hours_ago,
                             :end_time   => five_hours_ago + seven_hours,
                             :duration   => seven_hours,
                             :summary    => "Test scheduled maintenance for http")
      end
    end

    it "finds all scheduled maintenance with a particular summary" do
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)

      # Maintenance started in the past, still running
      ec.create_scheduled_maintenance(three_hours_ago, seven_hours, :summary => "Bring me a shrubbery!")
      # Current maintenance
      ec.create_scheduled_maintenance(t, half_an_hour, :summary => "Bring me a shrubbery!")
      # Future maintenance
      ec.create_scheduled_maintenance(t + five_minutes, half_an_hour, :summary => "Scheduled maintenance starting in 5 minutes")

      smp = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled', :reason => "Bring me a shrubbery!").sort_by { |k| k[:entity] }

      expect(smp).to be_an(Array)
      expect(smp.size).to eq(2)

      expect(smp[0]).to eq(:entity     => name,
                           :check      => check,
                           # The state here is nil due to no check having gone
                           # through for this item.  This is normally 'critical' or 'ok'
                           :state      => nil,
                           :start_time => three_hours_ago,
                           :end_time   => three_hours_ago + seven_hours,
                           :duration   => seven_hours,
                           :summary    => "Bring me a shrubbery!")
      expect(smp[1]).to eq(:entity     => name,
                           :check      => check,
                           # The state here is nil due to no check having gone
                           # through for this item.  This is normally 'critical' or 'ok'
                           :state      => nil,
                           :start_time => t,
                           :end_time   => t + half_an_hour,
                           :duration   => half_an_hour,
                           :summary    => "Bring me a shrubbery!")
    end

    it "finds all scheduled maintenance with a summary regex" do
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)

      # Maintenance started in the past, still running
      ec.create_scheduled_maintenance(three_hours_ago, seven_hours, :summary => "Bring me a shrubbery!")
      # Current maintenance
      ec.create_scheduled_maintenance(t, half_an_hour, :summary => "Bring me a shrubbery!")
      # Future maintenance
      ec.create_scheduled_maintenance(t + five_minutes, half_an_hour, :summary => "Scheduled maintenance starting in 5 minutes")

      smp = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled', :reason => '.* shrubbery!').sort_by { |k| k[:entity] }

      expect(smp).to be_an(Array)
      expect(smp.size).to eq(2)

      expect(smp[0]).to eq(:entity     => name,
                           :check      => check,
                           # The state here is nil due to no check having gone
                           # through for this item.  This is normally 'critical' or 'ok'
                           :state      => nil,
                           :start_time => three_hours_ago,
                           :end_time   => three_hours_ago + seven_hours,
                           :duration   => seven_hours,
                           :summary    => "Bring me a shrubbery!")
      expect(smp[1]).to eq(:entity     => name,
                           :check      => check,
                           # The state here is nil due to no check having gone
                           # through for this item.  This is normally 'critical' or 'ok'
                           :state      => nil,
                           :start_time => t,
                           :end_time   => t + half_an_hour,
                           :duration   => half_an_hour,
                           :summary    => "Bring me a shrubbery!")
    end

    it "deletes scheduled maintenance from list" do
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      # Current maintenance
      ec.create_scheduled_maintenance(two_hours_ago, seven_hours, :summary => "Scheduled maintenance started 2 hours ago")
      ec.create_scheduled_maintenance(t + half_an_hour, half_an_hour, :summary => "Scheduled maintenance starting in half an hour")
      # Future maintenance
      ec.create_scheduled_maintenance(t + five_minutes, half_an_hour, :summary => "Scheduled maintenance starting in 5 minutes")

      smp = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled').sort_by { |k| k[:entity] }

      expect(smp).to be_an(Array)
      expect(smp.size).to eq(3)

      expect(smp[0]).to eq(:entity     => name,
                           :check      => check,
                           # The state here is nil due to no check having gone
                           # through for this item.  This is normally 'critical' or 'ok'
                           :state      => nil,
                           :start_time => two_hours_ago,
                           :end_time   => two_hours_ago + seven_hours,
                           :duration   => seven_hours,
                           :summary    => "Scheduled maintenance started 2 hours ago")
      expect(smp[1]).to eq(:entity     => name,
                           :check      => check,
                           # The state here is nil due to no check having gone
                           # through for this item.  This is normally 'critical' or 'ok'
                           :state      => nil,
                           :start_time => t + five_minutes,
                           :end_time   => t + five_minutes + half_an_hour,
                           :duration   => half_an_hour,
                           :summary    => "Scheduled maintenance starting in 5 minutes")
      expect(smp[2]).to eq(:entity     => name,
                           :check      => check,
                           # The state here is nil due to no check having gone
                           # through for this item.  This is normally 'critical' or 'ok'
                           :state      => nil,
                           :start_time => t + half_an_hour,
                           :end_time   => t + half_an_hour + half_an_hour,
                           :duration   => half_an_hour,
                           :summary    => "Scheduled maintenance starting in half an hour")

      delete = Flapjack::Data::EntityCheck.delete_maintenance(:redis => @redis, :type => 'scheduled', :duration => '30 minutes' )
      expect(delete).to eq({})

      remain = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'scheduled').sort_by { |k| k[:entity] }

      expect(remain).to be_an(Array)
      expect(remain.size).to eq(1)

      expect(remain[0]).to eq(:entity     => name,
                              :check      => check,
                              # The state here is nil due to no check having gone
                              # through for this item.  This is normally 'critical' or 'ok'
                              :state      => nil,
                              :start_time => two_hours_ago,
                              :end_time   => two_hours_ago + seven_hours,
                              :duration   => seven_hours,
                              :summary    => "Scheduled maintenance started 2 hours ago")
    end

    it "deletes unscheduled maintenance from list" do
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      ec.create_unscheduled_maintenance(t, half_an_hour, :summary => "Unscheduled maintenance starting now")

      ump = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'unscheduled').sort_by { |k| k[:entity] }
      expect(ump).to be_an(Array)
      expect(ump.size).to eq(1)

      expect(ump[0]).to eq(:entity     => name,
                              :check      => check,
                              # The state here is nil due to no check having gone
                              # through for this item.  This is normally 'critical' or 'ok'
                              :state      => nil,
                              :start_time => t,
                              :duration   => half_an_hour,
                              :end_time   => t + half_an_hour,
                              :summary    => "Unscheduled maintenance starting now")

      later_t = t + (15 * 60)
      Delorean.time_travel_to(Time.at(later_t))

      delete = Flapjack::Data::EntityCheck.delete_maintenance(:redis => @redis, :type => 'unscheduled', :duration => '30 minutes')
      expect(delete).to eq({})

      remain = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'unscheduled').sort_by { |k| k[:entity] }
      expect(remain).to be_an(Array)
      expect(remain.size).to eq(1)

      expect(remain[0]).to eq(:entity     => name,
                              :check      => check,
                              # The state here is nil due to no check having gone
                              # through for this item.  This is normally 'critical' or 'ok'
                              :state      => nil,
                              :start_time => t,
                              :duration   => half_an_hour,
                              :end_time   => t + half_an_hour,
                              :summary    => "Unscheduled maintenance starting now")
    end

    it "shows errors when deleting maintenance in the past" do
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      ec.create_unscheduled_maintenance('14/3/1927 3pm', half_an_hour, :summary => "Unscheduled maintenance")
      t = Time.local(1927, 3, 14, 15, 0).to_i

      ump = Flapjack::Data::EntityCheck.find_maintenance(:redis => @redis, :type => 'unscheduled').sort_by { |k| k[:entity] }
      expect(ump).to be_an(Array)
      expect(ump.size).to eq(1)

      expect(ump[0]).to eq(:entity     => name,
                           :check      => check,
                           # The state here is nil due to no check having gone
                           # through for this item.  This is normally 'critical' or 'ok'
                           :state      => nil,
                           :start_time => t,
                           :duration   => half_an_hour,
                           :end_time   => t + half_an_hour,
                           :summary    => "Unscheduled maintenance")

      delete = Flapjack::Data::EntityCheck.delete_maintenance(:redis => @redis, :type => 'unscheduled', :duration => '30 minutes')
      expect(delete).to eq({"abc-123:ping:#{t}"=>"Maintenance can't be deleted as it finished in the past"})
    end
  end

  it "returns its state" do
    @redis.hset("check:#{name}:#{check}", 'state', 'ok')

    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
    state = ec.state
    expect(state).not_to be_nil
    expect(state).to eq('ok')
  end

  it "updates state" do
    @redis.hset("check:#{name}:#{check}", 'state', 'ok')

    old_timestamp = @redis.hget("check:#{name}:#{check}", 'last_update')

    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
    ec.update_state('critical')

    state = @redis.hget("check:#{name}:#{check}", 'state')
    expect(state).not_to be_nil
    expect(state).to eq('critical')

    new_timestamp = @redis.hget("check:#{name}:#{check}", 'last_update')
    expect(new_timestamp).not_to eq(old_timestamp)
  end

  it "updates enabled checks" do
    ts = Time.now.to_i
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
    ec.last_update = ts

    saved_check_ts = @redis.zscore("current_checks:#{name}", check)
    expect(saved_check_ts).not_to be_nil
    expect(saved_check_ts).to eq(ts)
    saved_entity_ts = @redis.zscore("current_entities", name)
    expect(saved_entity_ts).not_to be_nil
    expect(saved_entity_ts).to eq(ts)
  end

  it "exposes that it is enabled" do
    @redis.zadd("current_checks:#{name}", Time.now.to_i, check)
    @redis.zadd("current_entities", Time.now.to_i, name)
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)

    e = ec.enabled?
    expect(e).to be true
  end

  it "exposes that it is disabled" do
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)

    e = ec.enabled?
    expect(e).to be false
  end

  it "disables checks" do
    @redis.zadd("current_checks:#{name}", Time.now.to_i, check)
    @redis.zadd("current_entities", Time.now.to_i, name)
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
    ec.disable!

    saved_check_ts = @redis.zscore("current_checks:#{name}", check)
    saved_entity_ts = @redis.zscore("current_entities", name)
    expect(saved_check_ts).to be_nil
    expect(saved_entity_ts).to be_nil
  end

  it "does not update state with invalid value" do
    @redis.hset("check:#{name}:#{check}", 'state', 'ok')

    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
    ec.update_state('silly')

    state = @redis.hget("check:#{name}:#{check}", 'state')
    expect(state).not_to be_nil
    expect(state).to eq('ok')
  end

  it "does not update state with a repeated state value" do
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
    ec.update_state('critical', :summary => 'small problem', :details => 'none')
    changed_at = @redis.hget("check:#{name}:#{check}", 'last_change')
    summary = ec.summary
    details = ec.details

    ec.update_state('critical', :summary => 'big problem', :details => 'some')
    new_changed_at = @redis.hget("check:#{name}:#{check}", 'last_change')
    new_summary = ec.summary
    new_details = ec.details

    expect(changed_at).not_to be_nil
    expect(new_changed_at).not_to be_nil
    expect(new_changed_at).to eq(changed_at)

    expect(summary).not_to be_nil
    expect(new_summary).not_to be_nil
    expect(new_summary).not_to eq(summary)
    expect(summary).to eq('small problem')
    expect(new_summary).to eq('big problem')

    expect(details).not_to be_nil
    expect(new_details).not_to be_nil
    expect(new_details).not_to eq(details)
    expect(details).to eq('none')
    expect(new_details).to eq('some')
  end

  def time_before(t, min, sec = 0)
    t - ((60 * min) + sec)
  end

  it "returns a list of historical states for a time range" do
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)

    t = Time.now.to_i
    ec.update_state('ok', :timestamp => time_before(t, 5), :summary => 'a')
    ec.update_state('critical', :timestamp => time_before(t, 4), :summary => 'b')
    ec.update_state('ok', :timestamp => time_before(t, 3), :summary => 'c')
    ec.update_state('critical', :timestamp => time_before(t, 2), :summary => 'd')
    ec.update_state('ok', :timestamp => time_before(t, 1), :summary => 'e')

    states = ec.historical_states(time_before(t, 4), t)
    expect(states).not_to be_nil
    expect(states).to be_an(Array)
    expect(states.size).to eq(4)
    expect(states[0][:summary]).to eq('b')
    expect(states[1][:summary]).to eq('c')
    expect(states[2][:summary]).to eq('d')
    expect(states[3][:summary]).to eq('e')
  end

  it "returns a list of historical unscheduled maintenances for a time range" do
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)

    t = Time.now.to_i
    ec.update_state('ok', :timestamp => time_before(t, 5), :summary => 'a')
    ec.update_state('critical', :timestamp => time_before(t, 4), :summary => 'b')
    ec.update_state('ok', :timestamp => time_before(t, 3), :summary => 'c')
    ec.update_state('critical', :timestamp => time_before(t, 2), :summary => 'd')
    ec.update_state('ok', :timestamp => time_before(t, 1), :summary => 'e')

    states = ec.historical_states(time_before(t, 4), t)
    expect(states).not_to be_nil
    expect(states).to be_an(Array)
    expect(states.size).to eq(4)
    expect(states[0][:summary]).to eq('b')
    expect(states[1][:summary]).to eq('c')
    expect(states[2][:summary]).to eq('d')
    expect(states[3][:summary]).to eq('e')
  end

  it "returns a list of historical scheduled maintenances for a time range" do
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)

    t = Time.now.to_i

    ec.create_scheduled_maintenance(time_before(t, 180),
                                    half_an_hour, :summary => "a")
    ec.create_scheduled_maintenance(time_before(t, 120),
                                    half_an_hour, :summary => "b")
    ec.create_scheduled_maintenance(time_before(t, 60),
                                    half_an_hour, :summary => "c")

    sched_maint_periods = ec.maintenances(time_before(t, 150), t,
                                          :scheduled => true)
    expect(sched_maint_periods).not_to be_nil
    expect(sched_maint_periods).to be_an(Array)
    expect(sched_maint_periods.size).to eq(2)
    expect(sched_maint_periods[0][:summary]).to eq('b')
    expect(sched_maint_periods[1][:summary]).to eq('c')
  end

  it "returns that it has failed" do
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)

    @redis.hset("check:#{name}:#{check}", 'state', 'warning')
    expect(ec).to be_failed

    @redis.hset("check:#{name}:#{check}", 'state', 'critical')
    expect(ec).to be_failed

    @redis.hset("check:#{name}:#{check}", 'state', 'unknown')
    expect(ec).to be_failed
  end

  it "returns that it has not failed" do
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)

    @redis.hset("check:#{name}:#{check}", 'state', 'ok')
    expect(ec).not_to be_failed

    @redis.hset("check:#{name}:#{check}", 'state', 'acknowledgement')
    expect(ec).not_to be_failed
  end

  it "returns a status summary" do
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)

    t = Time.now.to_i
    ec.update_state('ok', :timestamp => time_before(t, 5), :summary => 'a')
    ec.update_state('critical', :timestamp => time_before(t, 4), :summary => 'b')
    ec.update_state('ok', :timestamp => time_before(t, 3), :summary => 'c')
    ec.update_state('critical', :timestamp => time_before(t, 2), :summary => 'd')

    summary = ec.summary
    expect(summary).to eq('d')
  end

  it "returns timestamps for its last notifications" do
    t = Time.now.to_i
    @redis.set("#{name}:#{check}:last_problem_notification", t - 30)
    @redis.set("#{name}:#{check}:last_acknowledgement_notification", t - 15)
    @redis.set("#{name}:#{check}:last_recovery_notification", t)

    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
    expect(ec.last_notification_for_state(:problem)[:timestamp]).to eq(t - 30)
    expect(ec.last_notification_for_state(:acknowledgement)[:timestamp]).to eq(t - 15)
    expect(ec.last_notification_for_state(:recovery)[:timestamp]).to eq(t)
  end

  it "finds all related contacts" do
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
    contacts = ec.contacts
    expect(contacts).not_to be_nil
    expect(contacts).to be_an(Array)
    expect(contacts.size).to eq(1)
    expect(contacts.first.name).to eq('John Johnson')
  end

  it "generates ephemeral tags for itself" do
    ec = Flapjack::Data::EntityCheck.for_entity_name('foo-app-01.example.com', 'Disk / Utilisation', :create_entity => true, :redis => @redis)
    tags = ec.tags
    expect(tags).not_to be_nil
    expect(tags).to be_a(Flapjack::Data::TagSet)
    expect(['foo-app-01', 'example.com', 'disk', '/', 'utilisation'].to_set.subset?(tags)).to be true
  end

  it "returns unacknowledged failing checks"

end
