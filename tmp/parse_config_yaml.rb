#!/usr/bin/env ruby

require 'yaml'

config = YAML.load(ARGF)
puts config.inspect

