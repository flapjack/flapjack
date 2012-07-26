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
      (state == 'ok') or (state == 'up')
    end

    def unknown?
      state == 'unknown'
    end

    def unreachable?
      state == 'unreachable'
    end

    def warning?
      state == 'warning'
    end

    def critical?
      state == 'critical'
    end

    def failure?
      warning? or critical?
    end

    def entity
      @attrs['entity'].downcase
    end

    def check
      @attrs['check']
    end

    def id
      entity + ':' + check
    end

    # FIXME: site specific
    def client
      entity.match(/^\w+/)[0]
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

