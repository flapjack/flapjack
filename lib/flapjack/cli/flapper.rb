#!/usr/bin/env ruby

desc 'Artificial service that oscillates up and down'
command :flapper do |flapper|
  flapper.action do |global_options,options,args|
    puts "flapper command ran"
  end
end
