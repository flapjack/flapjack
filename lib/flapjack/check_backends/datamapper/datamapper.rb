#!/usr/bin/env ruby 

require 'dm-core'
require 'dm-validations'
require 'dm-types'
require 'dm-timestamps'

Dir.glob(File.join(File.dirname(__FILE__), 'models', '*.rb')).each do |model|
  require model
end

module Flapjack
  module CheckBackends
    class Datamapper
      def initialize(options={})
        @options = options
        @config = OpenStruct.new(options)
      end
    end
  end
end

