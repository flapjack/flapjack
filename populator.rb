#!/usr/bin/env ruby

require 'bin/common'
require 'beanstalk-client'

begin 
  @jobs = Beanstalk::Pool.new(['localhost:11300'], 'jobs')
  1000.times do 
    @jobs.yput({:command => "sleep #{(1..5).to_a[rand(5)]}; echo '#{Time.now}'", 
                :params => {}, 
                :id => (1..100).to_a[rand(100)],
                :frequency => [10, 30, 60, 120][rand(4)],
                :offset => 0})
  end
rescue Beanstalk::NotConnected
  puts "beanstalk isn't up!"
  exit 2
end
  

