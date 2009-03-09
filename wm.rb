#!/usr/bin/env ruby

unless ARGV.size == 2 || ARGV.grep(/[--help|-h]/).size > 0
  puts "Usage: #{__FILE__} <number-of-workers> <host>"
  exit 1
end

number = ARGV[0].to_i

puts "Spinning up #{number} workers..."

number.times do
  cmd = "ruby #{File.join(File.dirname(__FILE__), 'worker.rb')} &"
  system(cmd)
end
