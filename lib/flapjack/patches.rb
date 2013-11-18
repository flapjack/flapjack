#!/usr/bin/env ruby

require 'logger'
require 'redis'

# bugfix for webrick's assuming 1.8.7 Logger syntax
class ::Logger; alias_method :write, :<<; end

# As Redis::Future objects inherit from BasicObject, it's difficult to
# distinguish between them and other objects in collected data from
# pipelined queries.
#
# (One alternative would be to put other values in Futures ourselves, and
#  evaluate everything...)
class Redis::Future; def class; ::Redis::Future; end; end
