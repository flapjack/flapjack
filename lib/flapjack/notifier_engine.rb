#!/usr/bin/env ruby

require 'ostruct'

module Flapjack
  class NotifierEngine
   
    attr_reader :log, :notifiers
  
    def initialize(opts={})
      @log = opts[:log]
      raise "you have to specify a logger" unless @log
      
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
   
    def notify!(options={})
      result     = options[:result]
      event      = options[:event]
      recipients = options[:recipients]

      raise ArgumentError, "A result + event were not passed!" unless result && event

      @notifiers.each do |n|
        recipients.each do |recipient|
          @log.info("Notifying #{recipient.name} via #{n.class} about check #{result.check_id}")
          n.notify(:result => result, :who => recipient, :event => event)
        end
      end
    end
  end
end
