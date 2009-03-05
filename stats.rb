#!/usr/bin/env ruby

require 'bin/common'
require 'beanstalk-client'

begin 
  beanstalk = Beanstalk::Pool.new(['localhost:11300'])
  loop do 
    time = Time.now
    beanstalk.list_tubes['localhost:11300'].each do |tube_name|
      next if tube_name == 'default'
      stats = beanstalk.stats_tube(tube_name)
      puts "#{time.to_i} [#{tube_name}] total: #{stats['total-jobs']}, waiting: #{stats['current-waiting']}, ready: #{stats['current-jobs-ready']}"
    end
    sleep 2
  end
rescue Beanstalk::NotConnected
  puts "beanstalk isn't up!"
  exit 2
end
  

