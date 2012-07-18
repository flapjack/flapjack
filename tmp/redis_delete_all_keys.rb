#!/usr/bin/env ruby

$: << File.dirname(__FILE__) + '/../lib' unless $:.include?(File.dirname(__FILE__) + '/../lib/')

require 'redis'

@persistence = Redis.new
keys = @persistence.keys '*'
@persistence.del(*keys)
