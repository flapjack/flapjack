module FixtureData

  # Not RSpec shared context, so it can be used in the pact provider too

  def check_data
    @check_data ||= {
     :id   => '1ed80833-6d28-4aba-8603-d81c249b8c23',
     :name => 'www.example.com:SSH',
     :initial_failure_delay => 30,
     :repeat_failure_delay  => 60,
     :enabled               => true
    }
  end

  def check_2_data
    @check_2_data ||= {
     :id   => '29e913cf-29ea-4ae5-94f6-7069cf4a1514',
     :name => 'www2.example.com:PING',
     :initial_failure_delay => 30,
     :repeat_failure_delay  => 60,
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
     :duration   => 3600,
     :summary    => 'working'
    }
  end

  def scheduled_maintenance_2_data
    @scheduled_maintenance_2_data ||= {
     :id         => '5a84c82b-0acb-4703-a27e-0b0db50b298a',
     :start_time => (time + 7200).iso8601,
     :duration   => 3600,
     :summary    => 'working'
    }
  end

  def unscheduled_maintenance_data
    @unscheduled_maintenance_data ||= {
     :id         => '9b7a7af4-8251-4216-8e86-2d4068447ae4',
     :duration   => 3600,
     :summary    => 'working'
    }
  end

  def unscheduled_maintenance_2_data
    @unscheduled_maintenance_2_data ||= {
     :id         => '41895714-9b77-48a9-a373-5f6005b1ce95',
     :duration   => 1800,
     :summary    => 'partly working'
    }
  end

  def sms_data
    @sms_data ||= {
      :id               => 'e2e09943-ed6c-476a-a8a5-ec165426f298',
      :type             => 'sms',
      :address          => '0123456789',
      :interval         => 300,
      :rollup_threshold => 5
    }
  end

  def email_data
    @email_data ||= {
      :id               => '9156de3c-ddc6-4637-b1cc-bd035fd61dd3',
      :type             => 'email',
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

  def tag_data
    @tag_data ||= {
     :id   => '3330972a-3bae-4d8d-af0f-e88caad73b49',
     :name => 'database',
    }
  end

  def tag_2_data
    @tag_2_data ||= {
     :id   => '72dfb8b1-e252-4c36-9bd1-7da774b17bba',
     :name => 'physical',
    }
  end

end