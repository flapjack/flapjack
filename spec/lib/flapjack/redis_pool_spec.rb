require 'spec_helper'
require 'flapjack/redis_pool'

describe Flapjack::RedisPool do

  it "is initialized" do
    EM.synchrony do
      redis_count = 3

      redis_conns = redis_count.times.collect {
        redis = double('redis')
        redis
      }
      expect(::Redis).to receive(:new).exactly(redis_count).times.and_return(*redis_conns)
      expect(Flapjack::Data::Migration).to receive(:correct_notification_rule_contact_linkages).exactly(redis_count).times
      expect(Flapjack::Data::Migration).to receive(:migrate_entity_check_data_if_required).exactly(redis_count).times
      expect(Flapjack::Data::Migration).to receive(:create_entity_ids_if_required).exactly(redis_count).times
      expect(Flapjack::Data::Migration).to receive(:clear_orphaned_entity_ids).exactly(redis_count).times
      expect(Flapjack::Data::Migration).to receive(:refresh_archive_index).exactly(redis_count).times
      expect(Flapjack::Data::Migration).to receive(:validate_scheduled_maintenance_periods).exactly(redis_count).times
      expect(Flapjack::Data::Migration).to receive(:correct_rollup_including_disabled_checks).exactly(redis_count).times
      expect(Flapjack::Data::Migration).to receive(:clear_pagerduty_username_and_password).exactly(redis_count).times

      frp = Flapjack::RedisPool.new(:size => redis_count)

      EM.stop
    end
  end

end
