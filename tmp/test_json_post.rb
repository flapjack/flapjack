#!/usr/bin/env ruby

require 'HTTParty'
require 'json'

@payload ={
    "email" => "phil@gmail.com",
    "token" => "mytokenstuff",
    "content" => "here is some content",
    "notification_type" => "1",
    "name" => "here is a name",
    "auto_action" => "true"
 }

HTTParty.post( 'http://localhost:4091/notification_rules', :body => JSON.dump(@payload), :options => { :headers => { 'ContentType' => 'application/json' } })

