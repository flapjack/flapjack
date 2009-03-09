#!/usr/bin/env ruby

50.times do
  cmd = "ruby #{File.join(File.dirname(__FILE__), 'worker.rb')} &"
  system(cmd)
end
