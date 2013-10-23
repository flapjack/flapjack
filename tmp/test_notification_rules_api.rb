#!/usr/bin/env ruby

require 'httparty'

require 'oj'
Oj.mimic_JSON
Oj.default_options = { :indent => 0, :mode => :strict }
require 'active_support/json'

class Foo

  include HTTParty
  base_uri "http://localhost:4091"

  @summary = ""

  #test_entity = "foo-app-1.example.com"
  test_entity = "localhost"
  test_check = "PING"
  test_contact = "21"
  test_email = '{
    "address": "dmitri@example.com",
    "interval": 900
  }'
  test_timezone = '{
    "timezone": "Australia/Broken_Hill"
  }'
  get_urls = [
    "/entities",
    "/checks/#{test_entity}",
    "/status/#{test_entity}",
    "/status/#{test_entity}/#{test_check}",
    "/outages/#{test_entity}",
    "/outages/#{test_entity}/#{test_check}",
    "/unscheduled_maintenances/#{test_entity}",
    "/unscheduled_maintenances/#{test_entity}/#{test_check}",
    "/scheduled_maintenances/#{test_entity}",
    "/scheduled_maintenances/#{test_entity}/#{test_check}",
    "/downtime/#{test_entity}",
    "/downtime/#{test_entity}/#{test_check}",
    "/contacts",
    "/contacts/#{test_contact}",
    "/contacts/#{test_contact}/notification_rules",
    "/contacts/#{test_contact}/media",
    "/contacts/#{test_contact}/media/email",
    "/contacts/#{test_contact}/timezone",
  ]

  test_rule = '{
      "contact_id": "21",
      "entity_tags": [
        "database",
        "physical"
      ],
      "entities": [
        "localhost"
      ],
      "time_restrictions": [
        {
          "TODO": "TODO"
        }
      ],
      "warning_media": [
        "email"
      ],
      "critical_media": [
        "sms",
        "email"
      ],
      "warning_blackhole": false,
      "critical_blackhole": false
    }'
  post_urls = {
    "/scheduled_maintenances/#{test_entity}/#{test_check}" => '{
      "start_time": 1361791228,
            "duration": 3600,
                "@summary": "SHUT IT ALL DOWN!"
    }',
    "/acknowledgements/#{test_entity}/#{test_check}" => '{
      "duration": 3600,
      "@summary": "AL - working on it"
    }',
    "/test_notifications/#{test_entity}/#{test_check}" => '',
    "/entities" => '{
      "entities": [
        {
          "id": "825",
          "name": "foo.example.com",
          "contacts": [
            "21",
            "22"
          ],
          "tags": [
            "foo"
          ]
        }
      ]
    }',
    "/contacts" => '{
      "contacts": [
        {
          "id": "21",
          "first_name": "Ada",
          "last_name": "Lovelace",
          "email": "ada@example.com",
          "media": {
            "sms": "+61412345678",
            "email": "ada@example.com"
          },
          "tags": [
            "legend",
            "first computer programmer"
          ]
        }
      ]
    }',
    "/notification_rules" => test_rule,
  }

  def self.do_get(url)
    response = get(url)
    response_body = response.body ? response.body[0..300] : nil
    puts "GET #{url}", "#{response.code} - #{response.message}", response.headers.inspect, response_body
    puts "---------------------------------------------------"
    @summary += "#{response.code} GET #{url}\n"
  end

  def self.do_post(url, body)
    response = post(url, :body => body, :headers => {'Content-Type' => 'application/json'})
    response_body = response.body ? response.body[0..300] : nil
    puts "POST #{url}", body, "#{response.code} - #{response.message}", response.headers.inspect, response_body
    puts "---------------------------------------------------"
    @summary += "#{response.code} POST #{url}\n"
  end

  def self.do_put(url, body)
    response = put(url, :body => body, :headers => {'Content-Type' => 'application/json'})
    response_body = response.body ? response.body[0..300] : nil
    puts "PUT #{url}", body, "#{response.code} - #{response.message}", response.headers.inspect, response_body
    puts "---------------------------------------------------"
    @summary += "#{response.code} PUT #{url}\n"
  end

  def self.do_delete(url)
    response = delete(url)
    response_body = response.body ? response.body[0..300] : nil
    puts "DELETE #{url}", "#{response.code} - #{response.message}", response.headers.inspect, response_body
    puts "---------------------------------------------------"
    @summary += "#{response.code} DELETE #{url}\n"
  end

  get_urls.each do |url|
    do_get(url)
  end

  post_urls.each_pair do |url, data|
    do_post(url, data)
  end

  rule = Oj.load(get('/contacts/21/notification_rules').body).last
  rule_id = rule['id']
  raise RuntimeError unless rule_id
  puts "****** NOTIFICATION RULE ID TO PICK ON (PUT, DELETE) IS: #{rule_id} ******"

  do_get("/notification_rules/#{rule_id}")
  do_put("/notification_rules/#{rule_id}", test_rule)
  do_delete("/contacts/21/media/email")
  do_put("/contacts/21/media/email", test_email)
  do_delete("/contacts/21/timezone")
  do_put("/contacts/21/timezone", test_timezone)

  puts "\nSummary:\n"
  puts @summary
end
