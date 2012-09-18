#!/usr/bin/env ruby

$: << File.dirname(__FILE__) + '/../lib' unless $:.include?(File.dirname(__FILE__) + '/../lib/')

require 'redis'

@persistence = Redis.new(:db => 13)
keys = @persistence.keys '*'
keys.each {|key|
  @persistence.del(key)
}
