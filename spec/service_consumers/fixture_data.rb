module FixtureData

  # Not RSpec shared context, so it can be used in the pact provider too

  def default_tear_down
    Flapjack.logger.messages.clear
    Flapjack.redis.flushdb
  end

  def api_host
    'example.org'
  end

  def fixture_time
    @fixture_time ||= Time.now
  end

  def resultify(data)
    ret = nil
    case data
    when Array
      ret = data.inject([]) do |memo, d|
        attrs = d[:attributes] || {}
        d.each_pair do |k, v|
          next if :attributes.eql?(k)
          attrs.update(k => v)
        end
        memo += [attrs]
        memo
      end
    when Hash
      ret = data[:attributes] || {}
      data.each_pair do |k, v|
        next if :attributes.eql?(k)
        ret.update(k => v)
      end
    else
      ret = data
    end
    ret
  end

  def check_data
    @check_data ||= {
     :id   => '1ed80833-6d28-4aba-8603-d81c249b8c23',
     :name => 'www.example.com:SSH',
     :enabled => true,
     :initial_failure_delay => nil,
     :repeat_failure_delay => nil,
     :initial_recovery_delay => nil
    }
  end

  def check_2_data
    @check_2_data ||= {
     :id   => '29e913cf-29ea-4ae5-94f6-7069cf4a1514',
     :name => 'www2.example.com:PING',
     :enabled => true,
     :initial_failure_delay => nil,
     :repeat_failure_delay => nil,
     :initial_recovery_delay => nil
    }
  end

  def check_json(ch_data)
    id = ch_data[:id]
    {
      :id => id,
      :type => 'check',
      :attributes => ch_data.reject {|k,v| :id.eql?(k) }
    }
  end

  def check_rel(ch_data)
    id = ch_data[:id]
    {
      :alerting_media => {
        :links => {
          :self => "http://#{api_host}/checks/#{id}/relationships/alerting_media",
          :related => "http://#{api_host}/checks/#{id}/alerting_media"
        }
      },
      :contacts => {
        :links => {
          :self => "http://#{api_host}/checks/#{id}/relationships/contacts",
          :related => "http://#{api_host}/checks/#{id}/contacts"
        }
       },
      :current_scheduled_maintenances =>  {
        :links => {
          :self => "http://#{api_host}/checks/#{id}/relationships/current_scheduled_maintenances",
          :related => "http://#{api_host}/checks/#{id}/current_scheduled_maintenances"
        }
      },
      :current_state => {
        :links => {
          :self => "http://#{api_host}/checks/#{id}/relationships/current_state",
          :related => "http://#{api_host}/checks/#{id}/current_state"
        }
      },
      :current_unscheduled_maintenance => {
        :links => {
          :self => "http://#{api_host}/checks/#{id}/relationships/current_unscheduled_maintenance",
          :related => "http://#{api_host}/checks/#{id}/current_unscheduled_maintenance"
        }
      },
      :latest_notifications => {
        :links => {
          :self => "http://#{api_host}/checks/#{id}/relationships/latest_notifications",
          :related => "http://#{api_host}/checks/#{id}/latest_notifications"
        }
      },
      :scheduled_maintenances => {
        :links => {
          :self => "http://#{api_host}/checks/#{id}/relationships/scheduled_maintenances",
          :related => "http://#{api_host}/checks/#{id}/scheduled_maintenances"
        }
      },
      :states => {
        :links => {
          :self => "http://#{api_host}/checks/#{id}/relationships/states",
          :related => "http://#{api_host}/checks/#{id}/states"
        }
      },
      :tags => {
        :links => {
          :self => "http://#{api_host}/checks/#{id}/relationships/tags",
          :related => "http://#{api_host}/checks/#{id}/tags"
        }
      },
      :unscheduled_maintenances => {
        :links => {
          :self => "http://#{api_host}/checks/#{id}/relationships/unscheduled_maintenances",
          :related => "http://#{api_host}/checks/#{id}/unscheduled_maintenances"
        }
      }
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

  def contact_json(co_data)
    id = co_data[:id]
    {
      :id => id,
      :type => 'contact',
      :attributes => co_data.reject {|k,v| :id.eql?(k) }
    }
  end

  def contact_rel(co_data)
    id = co_data[:id]
    {
      :checks => {
        :links => {
          :self => "http://#{api_host}/contacts/#{id}/relationships/checks",
          :related => "http://#{api_host}/contacts/#{id}/checks"
        }
      },
      :media => {
        :links => {
          :self => "http://#{api_host}/contacts/#{id}/relationships/media",
          :related => "http://#{api_host}/contacts/#{id}/media"
        }
      },
      :rules => {
        :links => {
          :self => "http://#{api_host}/contacts/#{id}/relationships/rules",
          :related => "http://#{api_host}/contacts/#{id}/rules"
        }
      },
      :tags => {
        :links => {
          :self => "http://#{api_host}/contacts/#{id}/relationships/tags",
          :related => "http://#{api_host}/contacts/#{id}/tags"
        }
      }
    }
  end

  def scheduled_maintenance_data
    @scheduled_maintenance_data ||= {
     :id         => '9b7a7af4-8251-4216-8e86-2d4068447ae4',
     :start_time => fixture_time.iso8601,
     :end_time   => (fixture_time + 3_600).iso8601,
     :summary    => 'working'
    }
  end

  def scheduled_maintenance_2_data
    @scheduled_maintenance_2_data ||= {
     :id         => '5a84c82b-0acb-4703-a27e-0b0db50b298a',
     :start_time => (fixture_time +  7_200).iso8601,
     :end_time   => (fixture_time + 10_800).iso8601,
     :summary    => 'working'
    }
  end

  def unscheduled_maintenance_data
    @unscheduled_maintenance_data ||= {
     :id         => '9b7a7af4-8251-4216-8e86-2d4068447ae4',
     :start_time => fixture_time.iso8601,
     :end_time   => (fixture_time + 3_600).iso8601,
     :summary    => 'working'
    }
  end

  def unscheduled_maintenance_2_data
    @unscheduled_maintenance_2_data ||= {
     :id         => '41895714-9b77-48a9-a373-5f6005b1ce95',
     :start_time => (fixture_time + 4_700).iso8601,
     :end_time   => (fixture_time + 5_400).iso8601,
     :summary    => 'partly working'
    }
  end

  def maintenance_json(type, m_data)
    {
      :id => m_data[:id],
      :type => "#{type}_maintenance",
      :attributes => m_data.reject {|k,v| :id.eql?(k) }
    }
  end

  def maintenance_rel(type, m_data)
    id = m_data[:id]
    {
      :check => {
        :links => {
          :self => "http://#{api_host}/#{type}_maintenances/#{id}/relationships/check",
          :related => "http://#{api_host}/#{type}_maintenances/#{id}/check"
        }
      }
    }
  end

  def sms_data
    @sms_data ||= {
      :id               => 'e2e09943-ed6c-476a-a8a5-ec165426f298',
      :transport        => 'sms',
      :address          => '0123456789',
      :interval         => 300,
      :rollup_threshold => 5,
      :pagerduty_subdomain => nil,
      :pagerduty_token => nil,
      :pagerduty_ack_duration => nil
    }
  end

  def email_data
    @email_data ||= {
      :id               => '9156de3c-ddc6-4637-b1cc-bd035fd61dd3',
      :transport        => 'email',
      :address          => 'ablated@example.org',
      :interval         => 180,
      :rollup_threshold => 3,
      :pagerduty_subdomain => nil,
      :pagerduty_token => nil,
      :pagerduty_ack_duration => nil
    }
  end

  def medium_json(me_data)
    id = me_data[:id]
    {
      :id => id,
      :type => 'medium',
      :attributes => me_data.reject {|k,v| :id.eql?(k) }
    }
  end

  def medium_rel(me_data)
    id = me_data[:id]
    {
      :alerting_checks => {
        :links => {
          :self => "http://#{api_host}/media/#{id}/relationships/alerting_checks",
          :related => "http://#{api_host}/media/#{id}/alerting_checks"
        }
      },
      :contact => {
        :links => {
          :self => "http://#{api_host}/media/#{id}/relationships/contact",
          :related => "http://#{api_host}/media/#{id}/contact"
        }
      },
      :rules => {
        :links => {
          :self => "http://#{api_host}/media/#{id}/relationships/rules",
          :related => "http://#{api_host}/media/#{id}/rules"
        }
      }
    }
  end

  def rule_data
    @rule_data ||= {
      :id          => '05983623-fcef-42da-af44-ed6990b500fa',
      :enabled     => true,
      :blackhole   => false,
      :strategy    => 'all_tags',
      :conditions_list => 'critical'
    }
  end

  def rule_2_data
    @rule_2_data ||= {
      :id          => '20f182fc-6e32-4794-9007-97366d162c51',
      :enabled     => true,
      :blackhole   => true,
      :strategy    => 'all_tags',
      :conditions_list => 'warning'
    }
  end

  def rule_json(ru_data)
    {
      :id => ru_data[:id],
      :type => 'rule',
      :attributes => ru_data.reject {|k,v| :id.eql?(k) }
    }
  end

  def rule_rel(ru_data)
    id = ru_data[:id]
    {
      :contact => {
        :links => {
          :self => "http://#{api_host}/rules/#{id}/relationships/contact",
          :related => "http://#{api_host}/rules/#{id}/contact"
        }
      },
      :media => {
        :links => {
          :self => "http://#{api_host}/rules/#{id}/relationships/media",
          :related => "http://#{api_host}/rules/#{id}/media"
        }
      },
      :tags => {
        :links => {
          :self => "http://#{api_host}/rules/#{id}/relationships/tags",
          :related => "http://#{api_host}/rules/#{id}/tags"
        }
      }
    }
  end

  def state_data
    @state_data ||= {
      :id => '142acf62-31e7-4074-ada9-a30ae73d880d',
      :created_at => (fixture_time - 30).iso8601,
      :updated_at => (fixture_time - 30).iso8601,
      :condition => 'critical',
    }
  end

  def state_2_data
    @state_2_data ||= {
      :id => '008d78fc-1c72-4c2a-8057-0d44b64c6f3d',
      :created_at => (fixture_time - 10).iso8601,
      :updated_at => (fixture_time - 10).iso8601,
      :condition => 'ok',
    }
  end

  def state_json(st_data)
    id = st_data[:id]
    {
      :id => id,
      :type => 'state',
      :attributes => st_data.reject {|k,v| :id.eql?(k) }
    }
  end

  def state_rel(st_data)
    id = st_data[:id]
    {
      :check => {
        :links => {
          :self => "http://#{api_host}/states/#{id}/relationships/check",
          :related => "http://#{api_host}/states/#{id}/check"
        }
      }
    }
  end

  def tag_data
    @tag_data ||= {
     :id => '1850b8d7-1055-4a6e-9c96-f8f50e55bd0f',
     :name => 'database',
    }
  end

  def tag_2_data
    @tag_2_data ||= {
     :id => 'c7a12328-8902-4974-8efa-68ec3e284507',
     :name => 'physical',
    }
  end

  def tag_json(ta_data)
    id = ta_data[:id]
    {
      :id => id,
      :type => 'tag',
      :attributes => ta_data.reject {|k,v| :id.eql?(k) }
    }
  end

  def tag_rel(ta_data)
    id = ta_data[:id]
    {
      :checks => {
        :links => {
          :self => "http://#{api_host}/tags/#{id}/relationships/checks",
          :related => "http://#{api_host}/tags/#{id}/checks"
        }
      },
      :contacts => {
        :links => {
          :self => "http://#{api_host}/tags/#{id}/relationships/contacts",
          :related => "http://#{api_host}/tags/#{id}/contacts"
        }
      },
      :rules => {
        :links => {
          :self => "http://#{api_host}/tags/#{id}/relationships/rules",
          :related => "http://#{api_host}/tags/#{id}/rules"
        }
      },
      :scheduled_maintenances => {
        :links => {
          :self => "http://#{api_host}/tags/#{id}/relationships/scheduled_maintenances",
          :related => "http://#{api_host}/tags/#{id}/scheduled_maintenances"
        }
      },
      :states => {
        :links => {
          :self => "http://#{api_host}/tags/#{id}/relationships/states",
          :related => "http://#{api_host}/tags/#{id}/states"
        }
      },
      :unscheduled_maintenances => {
        :links => {
          :self => "http://#{api_host}/tags/#{id}/relationships/unscheduled_maintenances",
          :related => "http://#{api_host}/tags/#{id}/unscheduled_maintenances"
        }
      }
    }
  end

  def metrics_data
    @metrics_data ||= {
      # :total_keys         => 0,  # test behaviour is inconsistent
      :processed_events   => {
        :all_events     => 0,
        :ok_events      => 0,
        :failure_events => 0,
        :action_events  => 0,
        :invalid_events => 0
      },
      :event_queue_length => 0,
      :check_freshness    => {:"0" => 0, :"60" => 0, :"300" => 0, :"900" => 0, :"3600" => 0},
      :check_counts       => {:all => 0, :enabled => 0, :failing => 0}
    }
  end

  def metrics_json(met_data)
    {
      :type => 'metrics',
      :attributes => met_data.reject {|k,v| :id.eql?(k) }
    }
  end

  def global_statistics_data
    @global_statistics_data ||= {
      :id => 'c63f8029-7c2b-4a33-b9f9-fbb2228c8037',
      :instance_name  => 'global',
      :created_at     => fixture_time.iso8601,
      :all_events     => 0,
      :ok_events      => 0,
      :failure_events => 0,
      :action_events  => 0,
      :invalid_events => 0
    }
  end

  def global_statistics_json
    {
      :id => global_statistics_data[:id],
      :type => 'statistic',
      :attributes => global_statistics_data.reject {|k,v| :id.eql?(k) }
    }
  end

  def acknowledgement_data
    @acknowledgement_data ||= {
      :id => '31b9378f-ae1c-4c78-ad34-2b35407c8bbd',
      :duration => 2 * 60 * 60,
      :summary => 'Giraffe'
    }
  end

  def acknowledgement_json(ack_data)
    {
      :id => ack_data[:id],
      :type => 'acknowledgement',
      :attributes => ack_data.reject {|k,v| :id.eql?(k) }
    }
  end

  def test_notification_data
    @test_notification_data ||= {
      :id => '8f78b421-4e89-4423-ab09-c0d76b4a698c',
      :summary => 'Rhinoceros'
    }
  end

  def test_notification_2_data
    @test_notification_2_data ||= {
      :id => 'a56c6ca5-c3c0-453d-96da-d09d459615e4',
      :summary => 'Tapir'
    }
  end

  def test_notification_json(tn_data)
    {
      :id => tn_data[:id],
      :type => 'test_notification',
      :attributes => tn_data.reject {|k,v| :id.eql?(k) }
    }
  end

end