#!/usr/bin/env ruby

require 'ostruct'

class Notifier
 
  attr_reader :recipients, :log

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
      @log.warning("there are no notifiers")
    end
  end
  
  def notify!(result)
    @notifiers.each do |n|
      @recipients.each do |recipient|
        @log.info("Notifying #{recipient.name} via #{n.class} about check #{result.id}")
        n.notify!(:result => result, :who => recipient)
      end
    end
  end
end

