#!/usr/bin/env ruby

require 'bin/common'
require 'beanstalk-client'

unless ARGV[0] || ARGV.grep(/[\-\-help|\-h]/).size > 0
  puts "Usage: #{__FILE__} <hostname>"
  exit 1
end

@host = ARGV[0]

begin 
  @jobs    = Beanstalk::Pool.new(["#{@host}:11300"], 'jobs')
  @results = Beanstalk::Pool.new(["#{@host}:11300"], 'results')
  loop do
    # get_job
    # perform_job
    # report_job
    puts 'waiting for jobs...'
    job = @jobs.reserve
    j = YAML::load(job.body)
    puts "processing #{j.inspect}"

    result = `#{j[:command]}`
    retval = $?.exitstatus

    puts "sending results for #{j[:id]}"
    @results.yput({:id => j[:id], 
                   :output => result, 
                   :retval => retval.to_i})
   
    # add job back onto stack
    @jobs.yput(j, 65536, j[:frequency])
      
    # once we're done, clean up
    job.delete
  end
rescue Beanstalk::NotConnected
  puts "beanstalk isn't up!"
  exit 2
end
  

