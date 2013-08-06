#!/usr/bin/env ruby

require 'redis'

require 'oj'
Oj.mimic_JSON
Oj.default_options = { :indent => 0, :mode => :strict }
require 'active_support/json'

redis = Redis.new(:db => 13)

message = {'notification_type'  => 'problem',
           'contact_first_name' => 'John',
           'contact_last_name' => 'Smith',
           'address' => 'johns@example.com',
           'state' => 'CRITICAL',
           'summary' => '',
       	   'last_state' => 'OK',
       	   'last_summary' => 'TEST',
       	   'details' => 'Testing',
       	   'time' => Time.now.to_i,
       	   'event_id' => 'app-02:ping'
       	}

redis.rpush('email_notifications', Oj.dump(message))
redis.lpush("email_notifications_actions", "+")