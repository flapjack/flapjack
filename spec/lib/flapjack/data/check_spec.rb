require 'spec_helper'

require 'flapjack/data/check'

describe Flapjack::Data::Check, :redis => true do

  let(:half_an_hour) { 30 * 60 }

  let(:check_name)  { 'foo.example.com:PING' }

  let(:redis) { Flapjack.redis }

  it "allows an id that is a UUID" do
    check = Flapjack::Data::Check.new(:id => '20f182fc-6e32-4794-9007-97366d162c51')
    check.valid?
    expect(check.errors).not_to be_nil
    expect(check.errors[:id]).to be_an(Array)
    expect(check.errors[:id]).to be_empty
  end

  it "does not allow an id that is not a UUID" do
    check = Flapjack::Data::Check.new(:id => 'hello')
    check.valid?
    expect(check.errors).not_to be_nil
    expect(check.errors[:id]).to be_an(Array)
    expect(check.errors[:id]).to include('is not a UUID')
  end

  context "maintenance" do

    it "returns that it is not in unscheduled maintenance" do
      Factory.check(:name => check_name)

      check = Flapjack::Data::Check.intersect(:name => check_name).all.first
      expect(check).not_to be_in_unscheduled_maintenance
    end

    it "returns that it is not in scheduled maintenance" do
      Factory.check(:name => check_name)

      check = Flapjack::Data::Check.intersect(:name => check_name).all.first
      expect(check).not_to be_in_scheduled_maintenance
    end

    it "adds an unscheduled maintenance period and ends the current one early", :time => true do
      Factory.check(:name => check_name)

      check = Flapjack::Data::Check.intersect(:name => check_name).all.first

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

      usms = check.unscheduled_maintenances.all
      expect(usms).to be_a(Set)
      expect(usms.size).to eq(2)
      expect(usms.map(&:summary)).to match_array(['scooby', 'shaggy'])

      expect(usms.map(&:end_time).map(&:to_i)).
        to match_array([later_t + half_an_hour, later_t])
    end

    it "ends an unscheduled maintenance period", :time => true do
      Factory.check(:name => check_name)

      check = Flapjack::Data::Check.intersect(:name => check_name).all.first

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

      usms = check.unscheduled_maintenances.all
      expect(usms).to be_a(Set)
      expect(usms.size).to eq(1)
      expect(usms.first.end_time.to_i).to eq(later_t.to_i)
    end

    it "ends a scheduled maintenance period for a future time" do
      Factory.check(:name => check_name)

      check = Flapjack::Data::Check.intersect(:name => check_name).all.first

      t = Time.now

      sm = Flapjack::Data::ScheduledMaintenance.new(:start_time => t.to_i + (60 * 60),
        :end_time => t.to_i + (3 * 60 * 60), :summary => '2 hours')
      sm.save
      check.scheduled_maintenances << sm

      sms = check.scheduled_maintenances.all
      expect(sms).to be_a(Set)
      expect(sms.size).to eq(1)
      expect(sms.first.summary).to eq('2 hours')

      check.end_scheduled_maintenance(sm, t)
      sms = check.scheduled_maintenances.all
      expect(sms).to be_a(Set)
      expect(sms).to be_empty
    end

    # maint period starts an hour from now, goes for two hours -- at 30 minutes into
    # it we stop it, and its duration should be 30 minutes
    it "shortens a scheduled maintenance period covering a current time", :time => true do
      Factory.check(:name => check_name)

      check = Flapjack::Data::Check.intersect(:name => check_name).all.first

      t = Time.now
      sm = Flapjack::Data::ScheduledMaintenance.new(:start_time => t.to_i + (60 * 60),
        :end_time => t.to_i + (3 * 60 * 60), :summary => '1 hour')
      sm.save
      check.scheduled_maintenances << sm

      future = Time.at(t.to_i + (90 * 60))

      Delorean.time_travel_to(future)

      check.end_scheduled_maintenance(sm, future)

      sms = check.scheduled_maintenances.all
      expect(sms).to be_a(Set)
      expect(sms.size).to eq(1)
      expect(sms.first.end_time.to_i).to eq(future.to_i)
    end

    it "does not alter or remove a scheduled maintenance period covering a past time", :time => true do
      Factory.check(:name => check_name)

      check = Flapjack::Data::Check.intersect(:name => check_name).all.first

      t = Time.now
      sm = Flapjack::Data::ScheduledMaintenance.new(:start_time => t.to_i + (60 * 60),
        :end_time => t.to_i + (3 * 60 * 60), :summary => '1 hour')
      sm.save
      check.scheduled_maintenances << sm

      future = Time.at(t.to_i + (6 * (60 * 60)) )

      Delorean.time_travel_to(future)

      check.end_scheduled_maintenance(sm, future)

      sms = check.scheduled_maintenances.all
      expect(sms).to be_a(Set)
      expect(sms.size).to eq(1)
      expect(sms.first.end_time.to_i).to eq(t.to_i + (3 * 60 * 60))
    end

  end

end
