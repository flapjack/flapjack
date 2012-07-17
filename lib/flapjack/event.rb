#!/usr/bin/env ruby

module Flapjack
  class Event
    def initialize(attrs={})
      @attrs = attrs
    end

    def state
      @attrs['state'].downcase
    end

    def ok?
      @attrs['state'].downcase == 'ok'
    end

    def unknown?
      @attrs['state'].downcase == 'unknown'
    end

    def warning?
      @attrs['state'].downcase == 'warning'
    end

    def critical?
      @attrs['state'].downcase == 'critical'
    end

    def host
      @attrs['host'].downcase
    end

    def service
      @attrs['service'].downcase
    end

    def id
      host + ':' + service
    end

    def client
      host.match(/^\w+/)[0]
    end

    def type
      @attrs['type'].downcase
    end

    def summary
      @attrs['summary']
    end

    def action?
      type == 'action'
    end

    def service?
      type == 'service'
    end

    def acknowledgement?
      action? and state == 'acknowledgement'
    end
  end
end

