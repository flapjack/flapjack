#!/usr/bin/env ruby

require "httparty"

class Foo

  include HTTParty
  base_uri "http://localhost:4091"

  #test_entity = "foo-app-1.example.com"
  test_entity = "localhost"
  test_check = "PING"

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
    "/contacts/1",
    "/contacts/1/notification_rules",
    "/notification_rules/1",
  ]

  get_urls.each do |url|
    response = self.get(url)
    puts "---------------------------------------------------"
    puts "GET #{url}", "#{response.code} - #{response.message}", response.headers.inspect, response.body[0..300]
    #format_get(url)
  end
  puts "---------------------------------------------------"

end
