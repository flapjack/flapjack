#!/usr/bin/env ruby

require 'httparty'

require 'flapjack'

@payload ={
    "email" => "phil@gmail.com",
    "token" => "mytokenstuff",
    "content" => "here is some content",
    "notification_type" => "1",
    "name" => "here is a name",
    "auto_action" => "true"
 }

HTTParty.post( 'http://localhost:4091/notification_rules',
               :body => Flapjack.dump_json(@payload),
               :options => { :headers => { 'ContentType' => 'application/json' } })

