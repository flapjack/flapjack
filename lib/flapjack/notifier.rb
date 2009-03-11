#!/usr/bin/env ruby

require 'ostruct'

class Notifier
  
  def initialize(opts={})
    @log = opts[:logger]
    @notifiers = (opts[:notifiers] || [])
    @recipients = (opts[:recipients] || [])
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

