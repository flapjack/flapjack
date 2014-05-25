require 'spec_helper'

require 'flapjack/data/check'
require 'flapjack/data/entity'

describe Flapjack::Data::Check, :redis => true do

  let(:half_an_hour) { 30 * 60 }

  let(:entity_name) { 'foo.example.com' }
  let(:check_name)  { 'PING' }

  let(:redis) { Flapjack.redis }

   it "finds all checks grouped by entity" do
    Factory.entity(:name => entity_name, :id => 1)
    entity = Flapjack::Data::Entity.find_by_id(1)
    Factory.check(entity, :entity_name => entity_name, :name => check_name, :id => 1,
      :enabled => true)

    checks_by_entity = Flapjack::Data::Check.hash_by_entity_name( Flapjack::Data::Check.all )
    expect(checks_by_entity).not_to be_nil
    expect(checks_by_entity).to be_a(Hash)
    expect(checks_by_entity.size).to eq(1)
    expect(checks_by_entity.keys.first).to eq(entity_name)
    checks = checks_by_entity[entity_name]
    expect(checks).not_to be_nil
    expect(checks.size).to eq(1)
    expect(checks.first.name).to eq(check_name)
  end

  it "finds all failing checks grouped by entity" do
    Factory.entity(:name => entity_name, :id => 1)
    entity = Flapjack::Data::Entity.find_by_id(1)
    Factory.check(entity, :entity_name => entity_name, :name => check_name, :id => 1,
      :state => 'ok', :enabled => true)
    Factory.check(entity, :entity_name => entity_name, :name => 'HTTP', :id => 2,
      :state => 'critical', :enabled => true)
    Factory.check(entity, :entity_name => entity_name, :name => 'FTP', :id => 3,
      :state => 'unknown', :enabled => true)

    failing_checks = Flapjack::Data::Check.
      intersect(:state => Flapjack::Data::CheckState.failing_states).all

    checks_by_entity = Flapjack::Data::Check.hash_by_entity_name( failing_checks  )
    expect(checks_by_entity).not_to be_nil
    expect(checks_by_entity).to be_a(Hash)
    expect(checks_by_entity.size).to eq(1)
    expect(checks_by_entity[entity_name].map(&:name)).to match_array(['HTTP', 'FTP'])
  end

  it "returns its entity's name" do
    Factory.entity(:name => entity_name, :id => 1)
    entity = Flapjack::Data::Entity.find_by_id(1)
    Factory.check(entity, :entity_name => entity_name, :name => check_name, :id => 1)

    check = Flapjack::Data::Check.intersect(:entity_name => entity_name, :name => check_name).all.first
    expect(check).not_to be_nil
    expect(check.entity_name).to eq(entity_name)
  end

  context "maintenance" do

    it "returns that it is not in unscheduled maintenance" do
      Factory.entity(:name => entity_name, :id => 1)
      entity = Flapjack::Data::Entity.find_by_id(1)
      Factory.check(entity, :entity_name => entity_name, :name => check_name, :id => 1)

      check = Flapjack::Data::Check.intersect(:entity_name => entity_name, :name => check_name).all.first
      expect(check).not_to be_in_unscheduled_maintenance
    end

    it "returns that it is not in scheduled maintenance" do
      Factory.entity(:name => entity_name, :id => 1)
      entity = Flapjack::Data::Entity.find_by_id(1)
      Factory.check(entity, :entity_name => entity_name, :name => check_name, :id => 1)

      check = Flapjack::Data::Check.intersect(:entity_name => entity_name, :name => check_name).all.first
      expect(check).not_to be_in_scheduled_maintenance
    end

    it "returns its current scheduled maintenance period" do
      Factory.entity(:name => entity_name, :id => 1)
      entity = Flapjack::Data::Entity.find_by_id(1)
      Factory.check(entity, :entity_name => entity_name, :name => check_name, :id => 1)

      t = Time.now

      check = Flapjack::Data::Check.intersect(:entity_name => entity_name, :name => check_name).all.first
      expect(check.scheduled_maintenance_at(t)).to be_nil

      sm = Flapjack::Data::ScheduledMaintenance.new(:start_time => t,
        :end_time => Time.at(t.to_i + 2400), :summary => 'planned')
      sm.save
      check.add_scheduled_maintenance(sm)

      lsm = Flapjack::Data::ScheduledMaintenance.new(:start_time => Time.at(t.to_i + 3600),
        :end_time => Time.at(t.to_i + 4800), :summary => 'later')
      lsm.save
      check.add_scheduled_maintenance(lsm)

      future = Time.at(t.to_i + 30)

      Delorean.time_travel_to(future)

      expect(check).to be_in_scheduled_maintenance

      csm = check.scheduled_maintenance_at(future)
      expect(csm).not_to be_nil
      expect(csm.summary).to eq('planned')
    end

    it "adds an unscheduled maintenance period" do
      Factory.entity(:name => entity_name, :id => 1)
      entity = Flapjack::Data::Entity.find_by_id(1)
      Factory.check(entity, :entity_name => entity_name, :name => check_name, :id => 1)

      check = Flapjack::Data::Check.intersect(:entity_name => entity_name, :name => check_name).all.first

      t = Time.now

      usm = Flapjack::Data::UnscheduledMaintenance.new(:start_time => t,
        :end_time => t + 2400, :summary => 'impromptu')
      usm.save
      check.set_unscheduled_maintenance(usm)

      Delorean.time_travel_to( Time.at(t.to_i + 15) )

      expect(check).to be_in_unscheduled_maintenance

      usms = check.unscheduled_maintenances_by_start.all
      expect(usms).to be_an(Array)
      expect(usms.size).to eq(1)
      expect(usms.first.summary).to eq('impromptu')
      usme = check.unscheduled_maintenances_by_end.all
      expect(usme).to be_an(Array)
      expect(usme.size).to eq(1)
      expect(usme.first.summary).to eq('impromptu')
    end

    it "adds an unscheduled maintenance period and ends the current one early", :time => true do
      Factory.entity(:name => entity_name, :id => 1)
      entity = Flapjack::Data::Entity.find_by_id(1)
      Factory.check(entity, :entity_name => entity_name, :name => check_name, :id => 1)

      check = Flapjack::Data::Check.intersect(:entity_name => entity_name, :name => check_name).all.first

      t = Time.now
      later_t = t.to_i + (15 * 60)
      usm_a = Flapjack::Data::UnscheduledMaintenance.new(:start_time => t,
        :end_time => t.to_i + half_an_hour, :summary => 'scooby')
      usm_a.save
      check.set_unscheduled_maintenance(usm_a)

      Delorean.time_travel_to( Time.at(later_t) )

      usm_b = Flapjack::Data::UnscheduledMaintenance.new(:start_time => later_t,
        :end_time => later_t + half_an_hour, :summary => 'shaggy')
      usm_b.save
      check.set_unscheduled_maintenance(usm_b)

      expect(check).to be_in_unscheduled_maintenance

      usms = check.unscheduled_maintenances_by_start.all
      expect(usms).to be_an(Array)
      expect(usms.size).to eq(2)
      expect(usms.map(&:summary)).to eq(['scooby', 'shaggy'])

      expect(usms.first.end_time.to_i).to eq(later_t)
      expect(usms.last.end_time.to_i).to eq(later_t + half_an_hour)
    end

    it "ends an unscheduled maintenance period", :time => true do
      Factory.entity(:name => entity_name, :id => 1)
      entity = Flapjack::Data::Entity.find_by_id(1)
      Factory.check(entity, :entity_name => entity_name, :name => check_name, :id => 1)

      check = Flapjack::Data::Check.intersect(:entity_name => entity_name, :name => check_name).all.first

      t = Time.now
      later_t = Time.at(t.to_i + (15 * 60))
      usm_a = Flapjack::Data::UnscheduledMaintenance.new(:start_time => t,
        :end_time => Time.at(t.to_i + half_an_hour), :summary => 'scooby')
      usm_a.save
      check.set_unscheduled_maintenance(usm_a)

      Delorean.time_travel_to( later_t )
      expect(check).to be_in_unscheduled_maintenance
      check.clear_unscheduled_maintenance(later_t)

      Delorean.time_travel_to( Time.at(later_t.to_i + 10) )

      expect(check).not_to be_in_unscheduled_maintenance

      usms = check.unscheduled_maintenances_by_start.all
      expect(usms).to be_an(Array)
      expect(usms.size).to eq(1)
      expect(usms.first.end_time.to_i).to eq(later_t.to_i)
    end

    it "ends a scheduled maintenance period for a future time" do
      Factory.entity(:name => entity_name, :id => 1)
      entity = Flapjack::Data::Entity.find_by_id(1)
      Factory.check(entity, :entity_name => entity_name, :name => check_name, :id => 1)

      check = Flapjack::Data::Check.intersect(:entity_name => entity_name, :name => check_name).all.first

      t = Time.now

      sm = Flapjack::Data::ScheduledMaintenance.new(:start_time => t.to_i + (60 * 60),
        :end_time => t.to_i + (3 * 60 * 60), :summary => '2 hours')
      sm.save
      check.add_scheduled_maintenance(sm)

      sms = check.scheduled_maintenances_by_start.all
      expect(sms).to be_an(Array)
      expect(sms.size).to eq(1)
      expect(sms.first.summary).to eq('2 hours')

      check.end_scheduled_maintenance(sm, t)
      sms = check.scheduled_maintenances_by_start.all
      expect(sms).to be_an(Array)
      expect(sms).to be_empty
    end

    # maint period starts an hour from now, goes for two hours -- at 30 minutes into
    # it we stop it, and its duration should be 30 minutes
    it "shortens a scheduled maintenance period covering a current time", :time => true do
      Factory.entity(:name => entity_name, :id => 1)
      entity = Flapjack::Data::Entity.find_by_id(1)
      Factory.check(entity, :entity_name => entity_name, :name => check_name, :id => 1)

      check = Flapjack::Data::Check.intersect(:entity_name => entity_name, :name => check_name).all.first

      t = Time.now
      sm = Flapjack::Data::ScheduledMaintenance.new(:start_time => t.to_i + (60 * 60),
        :end_time => t.to_i + (3 * 60 * 60), :summary => '1 hour')
      sm.save
      check.add_scheduled_maintenance(sm)

      future = Time.at(t.to_i + (90 * 60))

      Delorean.time_travel_to(future)

      check.end_scheduled_maintenance(sm, future)

      sms = check.scheduled_maintenances_by_start.all
      expect(sms).to be_an(Array)
      expect(sms.size).to eq(1)
      expect(sms.first.end_time.to_i).to eq(future.to_i)
    end

    it "does not alter or remove a scheduled maintenance period covering a past time", :time => true do
      Factory.entity(:name => entity_name, :id => 1)
      entity = Flapjack::Data::Entity.find_by_id(1)
      Factory.check(entity, :entity_name => entity_name, :name => check_name, :id => 1)

      check = Flapjack::Data::Check.intersect(:entity_name => entity_name, :name => check_name).all.first

      t = Time.now
      sm = Flapjack::Data::ScheduledMaintenance.new(:start_time => t.to_i + (60 * 60),
        :end_time => t.to_i + (3 * 60 * 60), :summary => '1 hour')
      sm.save
      check.add_scheduled_maintenance(sm)

      future = Time.at(t.to_i + (6 * (60 * 60)) )

      Delorean.time_travel_to(future)

      check.end_scheduled_maintenance(sm, future)

      sms = check.scheduled_maintenances_by_start.all
      expect(sms).to be_an(Array)
      expect(sms.size).to eq(1)
      expect(sms.first.end_time.to_i).to eq(t.to_i + (3 * 60 * 60))
    end

  end

  # it "updates state" do
  #   Flapjack.redis.hset("check:#{name}:#{check}", 'state', 'ok')

  #   check = Flapjack::Data::EntityCheck.for_entity_name(name, check)
  #   check.update_state('critical')

  #   state = Flapjack.redis.hget("check:#{name}:#{check}", 'state')
  #   state.should_not be_nil
  #   state.should == 'critical'
  # end

  # it "does not update state with a repeated state value" do
  #   ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
  #   ec.update_state('critical', :summary => 'small problem', :details => 'none')
  #   changed_at = @redis.hget("check:#{name}:#{check}", 'last_change')
  #   summary = ec.summary
  #   details = ec.details

  #   ec.update_state('critical', :summary => 'big problem', :details => 'some')
  #   new_changed_at = @redis.hget("check:#{name}:#{check}", 'last_change')
  #   new_summary = ec.summary
  #   new_details = ec.details

  #   expect(changed_at).not_to be_nil
  #   expect(new_changed_at).not_to be_nil
  #   expect(new_changed_at).to eq(changed_at)

  #   expect(summary).not_to be_nil
  #   expect(new_summary).not_to be_nil
  #   expect(new_summary).not_to eq(summary)
  #   expect(summary).to eq('small problem')
  #   expect(new_summary).to eq('big problem')

  #   expect(details).not_to be_nil
  #   expect(new_details).not_to be_nil
  #   expect(new_details).not_to eq(details)
  #   expect(details).to eq('none')
  #   expect(new_details).to eq('some')
  # end

  # def time_before(t, min, sec = 0)
  #   t - ((60 * min) + sec)
  # end

  # it "returns timestamps for its last notifications" do
  #   t = Time.now.to_i
  #   Flapjack.redis.set("#{name}:#{check}:last_problem_notification", t - 30)
  #   Flapjack.redis.set("#{name}:#{check}:last_acknowledgement_notification", t - 15)
  #   Flapjack.redis.set("#{name}:#{check}:last_recovery_notification", t)

  #   check = Flapjack::Data::EntityCheck.for_entity_name(name, check)
  #   check.last_notification_for_state(:problem)[:timestamp].should == t - 30
  #   check.last_notification_for_state(:acknowledgement)[:timestamp].should == t - 15
  #   check.last_notification_for_state(:recovery)[:timestamp].should == t
  # end

  # it "finds all related contacts" do
  #   check = Flapjack::Data::EntityCheck.for_entity_name(name, check)
  #   contacts = check.contacts
  #   contacts.should_not be_nil
  #   contacts.should be_an(Array)
  #   contacts.should have(1).contact
  #   contacts.first.name.should == 'John Johnson'
  # end

  # it "generates ephemeral tags for itself" do
  #   check = Flapjack::Data::EntityCheck.for_entity_name('foo-app-01.example.com', 'Disk / Utilisation')
  #   tags = check.tags
  #   tags.should_not be_nil
  #   tags.should be_a(Flapjack::Data::TagSet)
  #   ['foo-app-01', 'example.com', 'disk', '/', 'utilisation'].to_set.subset?(tags).should be_true
  # end

end
