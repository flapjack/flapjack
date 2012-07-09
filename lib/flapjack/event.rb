#!/usr/bin/env ruby

module Flapjack
  class Event
    def initialize(attrs={})
      @attrs = attrs
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
      host + ';' + service
    end
  end
end

