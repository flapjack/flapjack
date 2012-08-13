#!/usr/bin/env ruby

require 'em-resque/worker'
require 'flapjack/pikelet'

module Flapjack
  
  class Resqueuer

    include Flapjack::Pikelet

    # opts[:type] should be the notification class -- TODO clean this up,
    # it's all too hacky
    def initialize(opts = {})
      worker = EM::Resque::Worker.new(opts[:type].queue)
      
      # TODO check that this will 'block' indefinitely
      worker.work(0)
    end    
    
  end

end