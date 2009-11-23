#!/usr/bin/env ruby

require 'ostruct'

module Flapjack
  class Notifier
   
    attr_reader :recipients, :log, :notifiers
  
    def initialize(opts={})
      @log = opts[:logger]
      raise "you have to specify a logger" unless @log
      @recipients = (opts[:recipients] || [])
      
      @notifiers = []
      if opts[:notifiers]
        opts[:notifiers].each do |n|
          @notifiers << n
          @log.info("using the #{n.class.to_s.split("::").last} notifier")
        end
      else
        @log.warning("There are no notifiers! flapjack-notifier won't be useful.")
      end
    end
   
    # FIXME: use opts={} convention
    def notify!(result, event)
      @notifiers.each do |n|
        @recipients.each do |recipient|
          @log.info("Notifying #{recipient.name} via #{n.class} about check #{result.id}")
          n.notify(:result => result, :who => recipient, :event => event)
        end
      end
    end
  end
end
