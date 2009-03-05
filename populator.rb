#!/usr/bin/env ruby

require 'bin/common'
require 'beanstalk-client'

begin 
  @jobs = Beanstalk::Pool.new(['localhost:11300'], 'jobs')
  100.times do 
    @jobs.yput({:command => 'echo hello', :params => {}, :id => (1..100).to_a[rand(100)]})
  end
rescue Beanstalk::NotConnected
  puts "beanstalk isn't up!"
  exit 2
end
  

