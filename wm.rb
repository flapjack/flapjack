#!/usr/bin/env ruby

number = ARGV[0].to_i

puts "Spinning up #{number} workers..."

number.times do
  cmd = "ruby #{File.join(File.dirname(__FILE__), 'worker.rb')} &"
  system(cmd)
end
