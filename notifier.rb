#!/usr/bin/env ruby

require 'bin/common'
require 'beanstalk-client'

begin 
  @results = Beanstalk::Pool.new(['localhost:11300'], 'results')
  loop do
    puts 'waiting for results...'
    result = @results.reserve
    r = YAML::load(result.body)
    puts "processing #{r.inspect}"
    result.delete

  end
rescue Beanstalk::NotConnected
  puts "beanstalk isn't up!"
  exit 2
end
  

