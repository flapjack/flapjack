#!/usr/bin/env ruby

require 'bin/common'
require 'beanstalk-client'

begin 
  @jobs    = Beanstalk::Pool.new(['localhost:11300'], 'jobs')
  @results = Beanstalk::Pool.new(['localhost:11300'], 'results')
  loop do
    puts 'waiting for jobs...'
    job = @jobs.reserve
    j = YAML::load(job.body)
    puts "processing #{j.inspect}"
    job.delete
   
    puts "sending results for #{j[:id]}"
    @results.yput({:id => j[:id], 
                   :result => "Critical: 0, Warning: 0, 4 okay | value=4", 
                   :retval => 0})
    
    #sleep 5
  end
rescue Beanstalk::NotConnected
  puts "beanstalk isn't up!"
  exit 2
end
  

