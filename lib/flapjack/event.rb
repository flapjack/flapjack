#!/usr/bin/env ruby

module Flapjack
  class Event
    def initialize(attrs={})
      @attrs = attrs
    end

    def state
      @attrs['state']
    end

    def ok?
      @attrs['state'] == 'ok'
    end

    def unknown?
      @attrs['state'] == 'unknown'
    end

    def warning?
      @attrs['state'] == 'warning'
    end

    def critical?
      @attrs['state'] == 'critical'
    end

    def host
      @attrs['host']
    end

    def service
      @attrs['service']
    end

    def id
      host + ':' + service
    end

    def client
      host.match(/^\w+/)[0]
    end

    def type
      @attrs['type']
    end

    def summary
      @attrs['summary']
    end

    def action?
      @attrs['type'] == 'action'
    end

    def service?
      @attrs['type'] == 'service'
    end

    def acknowledgement?
      self.action? and @attrs['state'] == 'acknowledgement'
    end
  end
end

