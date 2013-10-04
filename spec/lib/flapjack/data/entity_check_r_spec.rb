require 'spec_helper'

require 'flapjack/data/entity_check_r'
require 'flapjack/data/entity_r'

describe Flapjack::Data::EntityCheckR, :redis => true do

  let(:half_an_hour) { 30 * 60 }

  # def create_contact
  #   redis.hmset('flapjack/data/contact_r:1:attrs', {'first_name' => 'John',
  #     'last_name' => 'Smith', 'email' => 'jsmith@example.com'}.flatten)
  #   redis.sadd('flapjack/data/contact_r::ids', '1')
  # end

  let(:entity_name) { 'foo.example.com' }
  let(:check_name)  { 'PING' }

  let(:redis) { Flapjack.redis }

  def create_entity(attrs = {})
    redis.multi
    redis.hmset("flapjack/data/entity_r:#{attrs[:id]}:attrs", {'name' => attrs[:name]}.flatten)
    redis.sadd('flapjack/data/entity_r::ids', attrs[:id])
    redis.sadd("flapjack/data/entity_r::by_name:set:#{attrs[:name]}", attrs[:id])
    redis.zadd("flapjack/data/entity_r::by_name:sorted_set:#{attrs[:name]}", 1, attrs[:id])
    redis.exec
  end

  def create_check(attrs = {})
    raise "entity not found" unless
      entity = Flapjack::Data::EntityR.intersect(:name => attrs[:entity_name]).all.first
    attrs[:state] ||= 'ok'
    redis.multi
    redis.hmset("flapjack/data/entity_check_r:#{attrs[:id]}:attrs", {'name' => attrs[:name],
      'entity_name' => entity.name, 'state' => attrs[:state], 'enabled' => (!!attrs[:enabled]).to_s}.flatten)
    redis.sadd('flapjack/data/entity_check_r::ids', attrs[:id])
    redis.sadd("flapjack/data/entity_check_r::by_name:set:#{attrs[:name]}", attrs[:id])
    redis.sadd("flapjack/data/entity_check_r::by_entity_name:set:#{entity.name}", attrs[:id])
    redis.sadd("flapjack/data/entity_check_r::by_state:set:#{attrs[:state]}", attrs[:id])
    redis.sadd("flapjack/data/entity_check_r::by_enabled:set:#{!!attrs[:enabled]}", attrs[:id])

    redis.zadd("flapjack/data/entity_check_r::by_name:sorted_set:#{attrs[:name]}", 1, attrs[:id])
    redis.zadd("flapjack/data/entity_check_r::by_entity_name:sorted_set:#{entity.name}", 1, attrs[:id])
    redis.zadd("flapjack/data/entity_check_r::by_state:sorted_set:#{attrs[:state]}", 1, attrs[:id])
    redis.zadd("flapjack/data/entity_check_r::by_enabled:sorted_set:#{!!attrs[:enabled]}", 1, attrs[:id])

    redis.sadd("flapjack/data/entity_r:#{entity.id}:check_ids", attrs[:id].to_s)
    redis.exec
  end

  it "finds all checks grouped by entity" do
    create_entity(:name => entity_name, :id => 1)
    create_check(:entity_name => entity_name, :name => check_name, :id => 1,
      :enabled => true)

    checks_by_entity = Flapjack::Data::EntityCheckR.hash_by_entity_name( Flapjack::Data::EntityCheckR.all )
    checks_by_entity.should_not be_nil
    checks_by_entity.should be_a(Hash)
    checks_by_entity.should have(1).entity
    checks_by_entity.keys.first.should == entity_name
    checks = checks_by_entity[entity_name]
    checks.should_not be_nil
    checks.should have(1).check
    checks.first.name.should == check_name
  end

  it "finds all failing checks grouped by entity" do
    create_entity(:name => entity_name, :id => 1)
    create_check(:entity_name => entity_name, :name => check_name, :id => 1,
      :state => 'ok', :enabled => true)
    create_check(:entity_name => entity_name, :name => 'HTTP', :id => 2,
      :state => 'critical', :enabled => true)
    create_check(:entity_name => entity_name, :name => 'FTP', :id => 3,
      :state => 'unknown', :enabled => true)

    failing_checks = Flapjack::Data::EntityCheckR.
      union(:state => Flapjack::Data::CheckStateR.failing_states).all

    checks_by_entity = Flapjack::Data::EntityCheckR.hash_by_entity_name( failing_checks  )
    checks_by_entity.should_not be_nil
    checks_by_entity.should be_a(Hash)
    checks_by_entity.should have(1).entity
    checks_by_entity[entity_name].map(&:name).should =~ ['HTTP', 'FTP']
  end

  it "finds all unacknowledged failing checks"

  it "returns its entity's name" do
    create_entity(:name => entity_name, :id => 1)
    create_check(:entity_name => entity_name, :name => check_name, :id => 1)

    ec = Flapjack::Data::EntityCheckR.intersect(:entity_name => entity_name, :name => check_name).all.first
    ec.should_not be_nil
    ec.entity_name.should == entity_name
  end

  context "maintenance" do

    it "returns that it is in unscheduled maintenance" do
      create_entity(:name => entity_name, :id => 1)
      create_check(:entity_name => entity_name, :name => check_name, :id => 1)
      Flapjack.redis.set("flapjack/data/entity_check_r:1:expiring:unscheduled_maintenance", 1)

      ec = Flapjack::Data::EntityCheckR.intersect(:entity_name => entity_name, :name => check_name).first
      ec.should be_in_unscheduled_maintenance
    end

    it "returns that it is not in unscheduled maintenance" do
      create_entity(:name => entity_name, :id => 1)
      create_check(:entity_name => entity_name, :name => check_name, :id => 1)

      ec = Flapjack::Data::EntityCheckR.intersect(:entity_name => entity_name, :name => check_name).first
      ec.should_not be_in_unscheduled_maintenance
    end

    it "returns that it is in scheduled maintenance" do
      create_entity(:name => entity_name, :id => 1)
      create_check(:entity_name => entity_name, :name => check_name, :id => 1)
      Flapjack.redis.set("flapjack/data/entity_check_r:1:expiring:scheduled_maintenance", 1)

      ec = Flapjack::Data::EntityCheckR.intersect(:entity_name => entity_name, :name => check_name).first
      ec.should be_in_scheduled_maintenance
    end

    it "returns that it is not in scheduled maintenance" do
      create_entity(:name => entity_name, :id => 1)
      create_check(:entity_name => entity_name, :name => check_name, :id => 1)

      ec = Flapjack::Data::EntityCheckR.intersect(:entity_name => entity_name, :name => check_name).first
      ec.should_not be_in_scheduled_maintenance
    end

    it "returns its current scheduled maintenance period" do
      create_entity(:name => entity_name, :id => 1)
      create_check(:entity_name => entity_name, :name => check_name, :id => 1)

      ec = Flapjack::Data::EntityCheckR.intersect(:entity_name => entity_name, :name => check_name).first
      ec.current_scheduled_maintenance.should be_nil

      t = Time.now.to_i

      sm = Flapjack::Data::ScheduledMaintenanceR.new(:start_time => t,
        :end_time => t + 2400, :summary => 'planned')
      ec.add_scheduled_maintenance(sm)

      lsm = Flapjack::Data::ScheduledMaintenanceR.new(:start_time => t + 3600,
        :end_time => t + 4800, :summary => 'later')
      ec.add_scheduled_maintenance(lsm)

      csm = ec.current_scheduled_maintenance
      csm.should_not be_nil
      csm.summary.should == 'planned'
    end

    it "adds an unscheduled maintenance period" do
      create_entity(:name => entity_name, :id => 1)
      create_check(:entity_name => entity_name, :name => check_name, :id => 1)

      ec = Flapjack::Data::EntityCheckR.intersect(:entity_name => entity_name, :name => check_name).first

      t = Time.now.to_i

      usm = Flapjack::Data::UnscheduledMaintenanceR.new(:start_time => t,
        :end_time => t + 2400, :summary => 'impromptu')
      ec.set_unscheduled_maintenance(usm)

      usms = ec.unscheduled_maintenances_by_start.all
      usms.should be_an(Array)
      usms.should have(1).unscheduled_maintenance_period
      usms.first.summary.should == 'impromptu'
      usme = ec.unscheduled_maintenances_by_end.all
      usme.should be_an(Array)
      usme.should have(1).unscheduled_maintenance_period
      usme.first.summary.should == 'impromptu'
    end

    it "adds an unscheduled maintenance period and ends the current one early", :time => true do
      create_entity(:name => entity_name, :id => 1)
      create_check(:entity_name => entity_name, :name => check_name, :id => 1)

      ec = Flapjack::Data::EntityCheckR.intersect(:entity_name => entity_name, :name => check_name).first

      t = Time.now.to_i
      later_t = t + (15 * 60)
      usm_a = Flapjack::Data::UnscheduledMaintenanceR.new(:start_time => t,
        :end_time => t + half_an_hour, :summary => 'scooby')
      ec.set_unscheduled_maintenance(usm_a)

      Delorean.time_travel_to( Time.at(later_t) )

      usm_b = Flapjack::Data::UnscheduledMaintenanceR.new(:start_time => later_t,
        :end_time => later_t + half_an_hour, :summary => 'shaggy')
      ec.set_unscheduled_maintenance(usm_b)

      ec.should be_in_unscheduled_maintenance

      usms = ec.unscheduled_maintenances_by_start.all
      usms.should be_an(Array)
      usms.should have(2).unscheduled_maintenance_periods
      usms.map(&:summary).should == ['scooby', 'shaggy']

      usms.first.end_time.to_i.should == later_t
      usms.last.end_time.to_i.should == later_t + half_an_hour
    end

    it "ends an unscheduled maintenance period", :time => true do
      create_entity(:name => entity_name, :id => 1)
      create_check(:entity_name => entity_name, :name => check_name, :id => 1)

      ec = Flapjack::Data::EntityCheckR.intersect(:entity_name => entity_name, :name => check_name).first

      t = Time.now.to_i
      later_t = t + (15 * 60)
      usm_a = Flapjack::Data::UnscheduledMaintenanceR.new(:start_time => t,
        :end_time => t + half_an_hour, :summary => 'scooby')
      ec.set_unscheduled_maintenance(usm_a)

      Delorean.time_travel_to( Time.at(later_t) )
      ec.should be_in_unscheduled_maintenance
      ec.clear_unscheduled_maintenance(later_t)
      ec.should_not be_in_unscheduled_maintenance

      usms = ec.unscheduled_maintenances_by_start.all
      usms.should be_an(Array)
      usms.should have(1).unscheduled_maintenance_period
      usms.first.end_time.to_i.should == later_t
    end

    it "ends a scheduled maintenance period for a future time" do
      create_entity(:name => entity_name, :id => 1)
      create_check(:entity_name => entity_name, :name => check_name, :id => 1)

      ec = Flapjack::Data::EntityCheckR.intersect(:entity_name => entity_name, :name => check_name).first

      t = Time.now.to_i

      sm = Flapjack::Data::ScheduledMaintenanceR.new(:start_time => t + (60 * 60),
        :end_time => t + (3 * 60 * 60), :summary => '2 hours')
      ec.add_scheduled_maintenance(sm)

      sms = ec.scheduled_maintenances_by_start.all
      sms.should be_an(Array)
      sms.should have(1).scheduled_maintenance_period
      sms.first.summary.should == '2 hours'

      ec.end_scheduled_maintenance(sm, t)
      sms = ec.scheduled_maintenances_by_start.all
      sms.should be_an(Array)
      sms.should be_empty
    end

    # maint period starts an hour from now, goes for two hours -- at 30 minutes into
    # it we stop it, and its duration should be 30 minutes
    it "shortens a scheduled maintenance period covering a current time", :time => true do
      create_entity(:name => entity_name, :id => 1)
      create_check(:entity_name => entity_name, :name => check_name, :id => 1)

      ec = Flapjack::Data::EntityCheckR.intersect(:entity_name => entity_name, :name => check_name).first

      t = Time.now.to_i
      sm = Flapjack::Data::ScheduledMaintenanceR.new(:start_time => t + (60 * 60),
        :end_time => t + (3 * 60 * 60), :summary => '1 hour')
      ec.add_scheduled_maintenance(sm)

      Delorean.time_travel_to( Time.at(t + (90 * 60)) )

      ec.end_scheduled_maintenance(sm, t + (90 * 60))

      sms = ec.scheduled_maintenances_by_start.all
      sms.should be_an(Array)
      sms.should have(1).scheduled_maintenance_period
      sms.first.end_time.to_i.should == t + (90 * 60)
    end

    it "does not alter or remove a scheduled maintenance period covering a past time", :time => true do
      create_entity(:name => entity_name, :id => 1)
      create_check(:entity_name => entity_name, :name => check_name, :id => 1)

      ec = Flapjack::Data::EntityCheckR.intersect(:entity_name => entity_name, :name => check_name).first

      t = Time.now.to_i
      sm = Flapjack::Data::ScheduledMaintenanceR.new(:start_time => t + (60 * 60),
        :end_time => t + (3 * 60 * 60), :summary => '1 hour')
      ec.add_scheduled_maintenance(sm)

      Delorean.time_travel_to( Time.at(t + (6 * (60 * 60)) ))

      ec.end_scheduled_maintenance(sm, t + (6 * (60 * 60)))

      sms = ec.scheduled_maintenances_by_start.all
      sms.should be_an(Array)
      sms.should have(1).scheduled_maintenance_period
      sms.first.end_time.to_i.should == t + (3 * 60 * 60)
    end

  end

  # it "updates state" do
  #   Flapjack.redis.hset("check:#{name}:#{check}", 'state', 'ok')

  #   ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
  #   ec.update_state('critical')

  #   state = Flapjack.redis.hget("check:#{name}:#{check}", 'state')
  #   state.should_not be_nil
  #   state.should == 'critical'
  # end

  # it "does not update state with a repeated state value" do
  #   ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
  #   ec.update_state('critical', :summary => 'small problem')
  #   changed_at = Flapjack.redis.hget("check:#{name}:#{check}", 'last_change')
  #   summary = Flapjack.redis.hget("check:#{name}:#{check}", 'summary')

  #   ec.update_state('critical', :summary => 'big problem')
  #   new_changed_at = Flapjack.redis.hget("check:#{name}:#{check}", 'last_change')
  #   new_summary = Flapjack.redis.hget("check:#{name}:#{check}", 'summary')

  #   changed_at.should_not be_nil
  #   new_changed_at.should_not be_nil
  #   new_changed_at.should == changed_at

  #   summary.should_not be_nil
  #   new_summary.should_not be_nil
  #   new_summary.should_not == summary
  #   summary.should == 'small problem'
  #   new_summary.should == 'big problem'
  # end

  # def time_before(t, min, sec = 0)
  #   t - ((60 * min) + sec)
  # end

  # it "returns timestamps for its last notifications" do
  #   t = Time.now.to_i
  #   Flapjack.redis.set("#{name}:#{check}:last_problem_notification", t - 30)
  #   Flapjack.redis.set("#{name}:#{check}:last_acknowledgement_notification", t - 15)
  #   Flapjack.redis.set("#{name}:#{check}:last_recovery_notification", t)

  #   ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
  #   ec.last_notification_for_state(:problem)[:timestamp].should == t - 30
  #   ec.last_notification_for_state(:acknowledgement)[:timestamp].should == t - 15
  #   ec.last_notification_for_state(:recovery)[:timestamp].should == t
  # end

  # it "finds all related contacts" do
  #   ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
  #   contacts = ec.contacts
  #   contacts.should_not be_nil
  #   contacts.should be_an(Array)
  #   contacts.should have(1).contact
  #   contacts.first.name.should == 'John Johnson'
  # end

  # it "generates ephemeral tags for itself" do
  #   ec = Flapjack::Data::EntityCheck.for_entity_name('foo-app-01.example.com', 'Disk / Utilisation')
  #   tags = ec.tags
  #   tags.should_not be_nil
  #   tags.should be_a(Flapjack::Data::TagSet)
  #   ['foo-app-01', 'example.com', 'disk', '/', 'utilisation'].to_set.subset?(tags).should be_true
  # end

end
