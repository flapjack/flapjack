#!/usr/bin/env ruby 

require 'dm-core'
require 'dm-validations'
require 'dm-types'
require 'dm-timestamps'

Dir.glob(File.join(File.dirname(__FILE__), 'models', '*.rb')).each do |model|
  require model
end
