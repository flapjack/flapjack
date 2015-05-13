module FixtureData

  # Not RSpec shared context, so it can be used in the pact provider too

  def default_tear_down
    Flapjack.logger.messages.clear
    Flapjack.redis.flushdb
  end

  def time
    @time ||= Time.now
  end

  def check_data
    @check_data ||= {
     :id   => '1ed80833-6d28-4aba-8603-d81c249b8c23',
     :name => 'www.example.com:SSH',
     :enabled               => true
    }
  end

  def check_2_data
    @check_2_data ||= {
     :id   => '29e913cf-29ea-4ae5-94f6-7069cf4a1514',
     :name => 'www2.example.com:PING',
     :enabled               => true
    }
  end

  def contact_data
    @contact_data ||= {
     :id       => 'c248da6f-ab16-4ce3-9b32-afd4e5f5270e',
     :name     => 'Jim Smith',
     :timezone => 'UTC',
    }
  end

  def contact_2_data
    @contact_2_data ||= {
     :id       => 'ff41bfbb-0d04-45e3-a4d2-579ed1655fb8',
     :name     => 'Joan Smith'
    }
  end

  def scheduled_maintenance_data
    @scheduled_maintenance_data ||= {
     :id         => '9b7a7af4-8251-4216-8e86-2d4068447ae4',
     :start_time => time.iso8601,
     :end_time   => (time + 3_600).iso8601,
     :summary    => 'working'
    }
  end

  def scheduled_maintenance_2_data
    @scheduled_maintenance_2_data ||= {
     :id         => '5a84c82b-0acb-4703-a27e-0b0db50b298a',
     :start_time => (time +  7_200).iso8601,
     :end_time   => (time + 10_800).iso8601,
     :summary    => 'working'
    }
  end

  def unscheduled_maintenance_data
    @unscheduled_maintenance_data ||= {
     :id         => '9b7a7af4-8251-4216-8e86-2d4068447ae4',
     :end_time   => (time + 3_600).iso8601,
     :summary    => 'working'
    }
  end

  def unscheduled_maintenance_2_data
    @unscheduled_maintenance_2_data ||= {
     :id         => '41895714-9b77-48a9-a373-5f6005b1ce95',
     :end_time   => (time + 5_400).iso8601,
     :summary    => 'partly working'
    }
  end

  def sms_data
    @sms_data ||= {
      :id               => 'e2e09943-ed6c-476a-a8a5-ec165426f298',
      :transport        => 'sms',
      :address          => '0123456789',
      :interval         => 300,
      :rollup_threshold => 5
    }
  end

  def email_data
    @email_data ||= {
      :id               => '9156de3c-ddc6-4637-b1cc-bd035fd61dd3',
      :transport        => 'email',
      :address          => 'ablated@example.org',
      :interval         => 180,
      :rollup_threshold => 3
    }
  end

  def notification_data
    @notification_data ||= {
      :id      => '8f78b421-4e89-4423-ab09-c0d76b4a698c',
      :summary => 'testing'
    }
  end

  def notification_2_data
    @notification_2_data ||= {
      :id      => 'a56c6ca5-c3c0-453d-96da-d09d459615e4',
      :summary => 'more testing'
    }
  end

  def pagerduty_credentials_data
    @pagerduty_credentials_data ||= {
      :id          => '87b65bf6-9cd8-4247-bd7d-70fcbe233b46',
      :service_key => 'abc',
      :subdomain   => 'def',
      :username    => 'ghi',
      :password    => 'jkl',
    }
  end

  def pagerduty_credentials_2_data
    @pagerduty_credentials_2_data ||= {
      :id          => 'cfd55e24-f572-42ae-a0eb-5f86bc8e900f',
      :service_key => 'mno',
      :subdomain   => 'pqr',
      :username    => 'stu',
      :password    => 'vwx',
    }
  end

  def route_data
    @route_data ||= {
      :id          => 'da37d2a9-da41-47ce-85ac-537b2ed1443a',
    }
  end

  def route_2_data
    @route_2_data ||= {
      :id          => '121fa5a6-7d87-43fc-a231-a746619ed98c',
    }
  end

  def rule_data
    @rule_data ||= {
      :id          => '05983623-fcef-42da-af44-ed6990b500fa',
    }
  end

  def rule_2_data
    @rule_2_data ||= {
      :id          => '20f182fc-6e32-4794-9007-97366d162c51',
    }
  end

  def state_data
    @state_data ||= {
     :name => 'ok',
    }
  end

  def tag_data
    @tag_data ||= {
     :name => 'database',
    }
  end

  def tag_2_data
    @tag_2_data ||= {
     :name => 'physical',
    }
  end

  def global_statistics_data
    @global_statistics_data ||= {
      :instance_name  => 'global',
      :created_at     => time.iso8601,
      :all_events     => 0,
      :ok_events      => 0,
      :failure_events => 0,
      :action_events  => 0,
      :invalid_events => 0
    }
  end

  def status_data
    @status_data ||= {
      :id => 'b25335ca-3e80-42e8-91b3-07026066b515',
      :last_update          => time.iso8601,
      :last_change          => time.iso8601,
      :last_problem         => (time - 20).iso8601,
      :last_recovery        => time.iso8601,
      :last_acknowledgement => (time - 10).iso8601,
      :summary              => 'all good',
      :details              => "trust me, it's ok"
    }
  end

end