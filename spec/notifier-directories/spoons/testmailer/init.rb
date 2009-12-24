#!/usr/bin/env ruby 

module Flapjack
  module Notifiers
    class Testmailer

      def initialize(opts={})
        @log = opts[:log]
      end

      def notify(opts={})
        @log.debug("TestMailer notifying #{opts[:who].name}")
      end
    
    end
  end
end



