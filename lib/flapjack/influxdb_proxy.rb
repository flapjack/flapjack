#!/usr/bin/env ruby

# defer initialisation for Redis connections until they're used.
require 'influxdb'

module Flapjack

  class << self
    # Thread and fiber-local
    def influxdb
      influxdb_cxn = Thread.current[:flapjack_influxdb]
      return influxdb_cxn unless influxdb_cxn.nil?
      Thread.current[:flapjack_influxdb] = Flapjack::InfluxDBProxy.new
    end
  end

  class InfluxDBProxy

    class << self
      attr_accessor :config
    end

    def respond_to?(name, include_private = false)
      proxied_connection.respond_to?(name, include_private)
    end

    def method_missing(name, *args, &block)
      proxied_connection.send(name, *args, &block)
    end

    private

    def proxied_connection
      return @proxied_connection unless @proxied_connection.nil?
      @proxied_connection = ::InfluxDB::Client.new(self.class.config)
    end

  end

end
