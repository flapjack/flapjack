require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::ScheduledMaintenances', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:check) { double(Flapjack::Data::Check, :id => check_data[:id]) }

  it "creates a scheduled maintenance period for a check" # do
  #   start = Time.now + (60 * 60) # an hour from now
  #   duration = (2 * 60 * 60)     # two hours

  #   expect(Flapjack::Data::Check).to receive(:lock).
  #     with(Flapjack::Data::ScheduledMaintenance).and_yield

  #   expect(Flapjack::Data::Check).to receive(:find_by_ids!).
  #     with(check.id).and_return([check])

  #   sched_maint = double(Flapjack::Data::ScheduledMaintenance)
  #   expect(sched_maint).to receive(:invalid?).and_return(false)
  #   expect(sched_maint).to receive(:save).and_return(true)
  #   expect(check).to receive(:add_scheduled_maintenance).with(sched_maint)
  #   expect(Flapjack::Data::ScheduledMaintenance).to receive(:new).
  #     with(:start_time => start.getutc.to_i,
  #          :end_time => start.getutc.to_i + duration,
  #          :summary => 'test').
  #     and_return(sched_maint)

  #   post "/scheduled_maintenances/checks/#{check.id}",
  #     Flapjack.dump_json(:scheduled_maintenances => [{:start_time => start.iso8601, :summary => 'test', :duration => duration}]),
  #     jsonapi_post_env
  #   expect(last_response.status).to eq(204)
  # end

  it "doesn't create a scheduled maintenance period for a check if the start time isn't passed" # do
  #   duration = (2 * 60 * 60)     # two hours

  #   post "/scheduled_maintenances/checks/#{check.id}",
  #     Flapjack.dump_json(:summary => 'test', :duration => duration), jsonapi_post_env
  #   expect(last_response.status).to eq(403)
  # end

  it "deletes a scheduled maintenance period for an entity check" # do
  #   start_time = Time.now + (60 * 60) # an hour from now

  #   sched_maint = double(Flapjack::Data::ScheduledMaintenance)
  #   sched_maints = double('sched_maints', :all => [sched_maint])
  #   sm_range = double('sm_range')
  #   expect(sm_range).to receive(:intersect_range).
  #     with(start_time.to_i, start_time.to_i, :by_score => true).
  #     and_return(sched_maints)

  #   expect(check).to receive(:scheduled_maintenances_by_start).and_return(sm_range)
  #   expect(check).to receive(:end_scheduled_maintenance).with(sched_maint, an_instance_of(Time))

  #   expect(Flapjack::Data::Check).to receive(:find_by_ids!).
  #     with(check.id).and_return([check])

  #   delete "/scheduled_maintenances/checks/#{check.id}",
  #     :start_time => start_time.iso8601
  #   expect(last_response.status).to eq(204)
  # end

  it "doesn't delete a scheduled maintenance period for a check if the start time isn't passed" # do
  #   expect(check).not_to receive(:end_scheduled_maintenance)

  #   delete "/scheduled_maintenances/checks/#{check.id}"
  #   expect(last_response.status).to eq(403)
  # end

  it "deletes scheduled maintenance periods for multiple checks" # do
  #   start_time = Time.now + (60 * 60) # an hour from now

  #   check_2 = double(Flapjack::Data::Check, :id => '9012')

  #   sched_maint = double(Flapjack::Data::ScheduledMaintenance)
  #   sched_maints = double('sched_maints', :all => [sched_maint])
  #   sm_range = double('sm_range')
  #   expect(sm_range).to receive(:intersect_range).
  #     with(start_time.to_i, start_time.to_i, :by_score => true).
  #     and_return(sched_maints)

  #   sched_maint_2 = double(Flapjack::Data::ScheduledMaintenance)
  #   sched_maints_2 = double('sched_maints', :all => [sched_maint_2])
  #   sm_range_2 = double('sm_range')
  #   expect(sm_range_2).to receive(:intersect_range).
  #     with(start_time.to_i, start_time.to_i, :by_score => true).
  #     and_return(sched_maints_2)

  #   expect(check).to receive(:scheduled_maintenances_by_start).and_return(sm_range)
  #   expect(check).to receive(:end_scheduled_maintenance).with(sched_maint, an_instance_of(Time))

  #   expect(check_2).to receive(:scheduled_maintenances_by_start).and_return(sm_range_2)
  #   expect(check_2).to receive(:end_scheduled_maintenance).with(sched_maint_2, an_instance_of(Time))

  #   expect(Flapjack::Data::Check).to receive(:find_by_ids!).
  #     with(check.id, check_2.id).and_return([check, check_2])

  #   delete "/scheduled_maintenances/checks/#{check.id},#{check_2.id}",
  #     :start_time => start_time.iso8601
  #   expect(last_response.status).to eq(204)
  # end

end
